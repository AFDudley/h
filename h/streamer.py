# -*- coding: utf-8 -*-
import copy
import datetime
import json
import logging
import operator
import re
import unicodedata
import urlparse

from dateutil.tz import tzutc
from jsonpointer import resolve_pointer
from jsonschema import validate
from pyramid.events import subscriber
from pyramid_sockjs.session import Session
import transaction

from h import events, interfaces

log = logging.getLogger(__name__)  # pylint: disable=invalid-name


def unidecode(text, normalization='NFKD'):
    # Convert str to unicode
    if isinstance(text, str):
        text = unicode(text, "utf-8")

    # Do not touch other types
    if not isinstance(text, unicode):
        return text

    text = unicodedata.normalize(normalization, text)
    return u"".join([c for c in text if not unicodedata.combining(c)])


filter_schema = {
    "type": "object",
    "properties": {
        "name": {"type": "string", "optional": True},
        "match_policy": {
            "type": "string",
            "enum": ["include_any", "include_all",
                     "exclude_any", "exclude_all"]
        },
        "actions": {
            "create": {"type": "boolean", "default":  True},
            "update": {"type": "boolean", "default":  True},
            "delete": {"type": "boolean", "default":  True},
        },
        "clauses": {
            "type": "array",
            "items": {
                "field": {"type": "string", "format": "json-pointer"},
                "operator": {
                    "type": "string",
                    "enum": ["equals", "matches", "lt", "le", "gt", "ge",
                             "one_of", "first_of", "match_of",
                             "lene", "leng", "lenge", "lenl", "lenle"]
                },
                "value": "object",
                "case_sensitive": {"type": "boolean", "default": True},
                "options": {"type": "object", "default": {}}
            }
        },
        "past_data": {
            "load_past": {
                "type": "string",
                "enum": ["time", "hits", "none"]
            },
            "go_back": {"type": "minutes", "default": 5},
            "hits": {"type": "number", "default": 100},
        }
    },
    "required": ["match_policy", "clauses", "actions"]
}

len_operators = {
    "lene": "=",
    "leng": ">",
    "lenge": ">=",
    "lenl": "<",
    "lenle": "<="
}


class FilterToElasticFilter(object):
    def __init__(self, filter_json, request):
        self.request = request
        self.filter = filter_json
        self.query = {
            "sort": [
                {"updated": {"order": "desc"}}
            ],
            "query": {
                "bool": {
                    "minimum_number_should_match": 1}}}
        self.filter_scripts_to_add = []

        if len(self.filter['clauses']):
            clauses = self.convert_clauses(self.filter['clauses'])
            # apply match policy
            policy = getattr(self, self.filter['match_policy'])
            policy(self.query['query']['bool'], clauses)
        else:
            self.query['query'] = {"match_all": {}}

        if self.filter['past_data']['load_past'] == 'time':
            back = self.filter['past_data']['go_back']
            now = datetime.datetime.utcnow().replace(tzinfo=tzutc())
            delta = datetime.timedelta(minutes=back)
            past = now - delta
            converted = past.strftime("%Y-%m-%dT%H:%M:%S")
            self.query['filter'] = {"range": {"created": {"gte": converted}}}
        elif self.filter['past_data']['load_past'] == 'hits':
            self.query['size'] = self.filter['past_data']['hits']

        if len(self.filter_scripts_to_add):
            if 'filter' not in self.query:
                self.query['filter'] = {}
            scripts = ' AND '.join(self.filter_scripts_to_add)
            self.query['filter']['script'] = '"script": ' + scripts

    @staticmethod
    def equals(field, value):
        if type(value) is list:
            return {"terms": {field: value}}
        else:
            return {"term": {field: value}}

    @staticmethod
    def one_of(field, value):
        if type(value) is list:
            return {"terms": {field: value}}
        else:
            return {"term": {field: value}}

    @staticmethod
    def first_of(field, value):
        if type(value) is list:
            return {"terms": {field: value}}
        else:
            return {"term": {field: value}}

    @staticmethod
    def match_of(field, value):
        if type(value) is list:
            return {"terms": {field: value}}
        else:
            return {"term": {field: value}}

    @staticmethod
    def matches(field, value):
        if type(value) is list:
            return {"terms": {field: value}}
        else:
            return {"term": {field: value}}

    @staticmethod
    def lt(field, value):
        return {"range": {field: {"lt": value}}}

    @staticmethod
    def le(field, value):
        return {"range": {field: {"lte": value}}}

    @staticmethod
    def gt(field, value):
        return {"range": {field: {"gt": value}}}

    @staticmethod
    def ge(field, value):
        return {"range": {field: {"gte": value}}}

    def convert_clauses(self, clauses):
        new_clauses = []
        for clause in clauses:
            if isinstance(clause['field'], list):
                field = []
                for f in clause['field']:
                    field.append(f[1:].replace('/', '.'))
            else:
                field = clause['field'][1:].replace('/', '.')
            es = clause['options']['es'] if 'es' in clause['options'] else None
            if es:
                query_type = es.get('query_type', 'simple')
            else:
                query_type = 'simple'

            if clause.get('case_sensitive', True):
                value = clause['value']
            else:
                if type(clause['value']) is list:
                    value = [x.lower() for x in clause['value']]
                else:
                    value = clause['value'].lower()

            if query_type == 'query_string':
                # Generate query_string query
                escaped_value = re.escape(value)
                new_clause = {
                    "query_string": {
                        "query": "*" + escaped_value + "*",
                        "fields": [field]
                    }
                }
            elif query_type == 'match':
                cutoff_freq = es['cutoff_frequency'] if 'cutoff_frequency' in es else None
                and_or = es['and_or'] if 'and_or' in es else 'and'
                message = {
                    "query": value,
                    "operator": and_or
                }
                if cutoff_freq:
                    message['cutoff_frequency'] = cutoff_freq
                new_clause = {"match": {field: message}}
            elif query_type == 'multi_match':
                and_or = es['and_or'] if 'and_or' in es else 'and'
                match_type = es['match_type'] if 'mach_type' in es else 'cross_fields'
                message = {
                    "query": value,
                    "operator": and_or,
                    "type": match_type,
                    "fields": es['fields']
                }
                new_clause = {"multi_match": message}
            elif clause['operator'][0:2] == 'len':
                script = "doc['%s'].values.length %s %s" % (
                    field,
                    len_operators[clause['operator']],
                    clause[value]
                )
                self.filter_scripts_to_add.append(script)
            else:
                new_clause = getattr(self, clause['operator'])(field, value)

            new_clauses.append(new_clause)
        return new_clauses

    @staticmethod
    def _policy(oper, target, clauses):
        target[oper] = []
        for clause in clauses:
            target[oper].append(clause)

    def include_any(self, target, clauses):
        self._policy('should', target, clauses)

    def include_all(self, target, clauses):
        self._policy('must', target, clauses)

    def exclude_any(self, target, clauses):
        self._policy('must_not', target, clauses)

    def exclude_all(self, target, clauses):
        target['must_not'] = {"bool": {}}
        self._policy('must', target['must_not']['bool'], clauses)


def first_of(a, b):
    return a[0] == b
setattr(operator, 'first_of', first_of)


def match_of(a, b):
    for subb in b:
        if subb in a:
            return True
    return False
setattr(operator, 'match_of', match_of)


def lene(a, b):
    return len(a) == b
setattr(operator, 'lene', lene)


def leng(a, b):
    return len(a) > b
setattr(operator, 'leng', leng)


def lenge(a, b):
    return len(a) >= b
setattr(operator, 'lenge', lenge)


def lenl(a, b):
    return len(a) < b
setattr(operator, 'lenl', lenl)


def lenle(a, b):
    return len(a) <= b
setattr(operator, 'lenle', lenle)


class FilterHandler(object):
    def __init__(self, filter_json):
        self.filter = filter_json

    # operators
    operators = {
        'equals': 'eq',
        'matches': 'contains',
        'lt': 'lt',
        'le': 'le',
        'gt': 'gt',
        'ge': 'ge',
        'one_of': 'contains',
        'first_of': 'first_of',
        'match_of': 'match_of',
        'lene': 'lene',
        'leng': 'leng',
        'lenge': 'lenge',
        'lenl': 'lenl',
        'lenle': 'lenle',
    }

    def evaluate_clause(self, clause, target):
        if isinstance(clause['field'], list):
            for field in clause['field']:
                copied = copy.deepcopy(clause)
                copied['field'] = field
                result = self.evaluate_clause(copied, target)
                if result:
                    return True
            return False
        else:
            field_value = resolve_pointer(target, clause['field'], None)
            if field_value is None:
                return False

            # pylint: disable=maybe-no-member
            if clause.get('case_sensitive', True):
                cval = clause['value']
                fval = field_value
            else:
                if type(clause['value']) is list:
                    cval = [x.lower() for x in clause['value']]
                else:
                    cval = clause['value'].lower()

                if type(field_value) is list:
                    fval = [x.lower() for x in field_value]
                else:
                    fval = field_value.lower()

            if clause.get('normalize', False):
                if type(cval) is list:
                    tval = []
                    for cv in cval:
                        if isinstance(cv, str):
                            cv = unicode(cv, "utf-8")
                        if isinstance(cv, unicode):
                            tval.append(unidecode(cv))
                        else:
                            tval.append(cv)
                    cval = tval
                else:
                    if isinstance(cval, str):
                        cval = unicode(cval, "utf-8")
                    if isinstance(cval, unicode):
                        cval = unidecode(cval)

                if type(fval) is list:
                    tval = []
                    for fv in fval:
                        if isinstance(fv, str):
                            fv = unicode(fv, "utf-8")
                        if isinstance(fv, unicode):
                            tval.append(unidecode(fv))
                        else:
                            tval.append(fv)
                    fval = tval
                else:
                    if isinstance(fval, str):
                        fval = unicode(fval, "utf-8")
                    if isinstance(fval, unicode):
                        fval = unidecode(fval)
            # pylint: enable=maybe-no-member

            reversed_order = False
            # Determining operator order
            # Normal order: field_value, clause['value']
            # i.e. condition created > 2000.01.01
            # Here clause['value'] = '2001.01.01'.
            # The field_value is target['created']
            # So the natural order is: ge(field_value, clause['value']

            # But!
            # Reversed operator order for contains (b in a)
            if type(cval) is list or type(fval) is list:
                if clause['operator'] in ['one_of', 'matches']:
                    reversed_order = True
                    # But not in every case. (i.e. tags matches 'b')
                    # Here field_value is a list, because an annotation can
                    # have many tags.
                    if type(field_value) is list:
                        reversed_order = False

            if reversed_order:
                lval = cval
                rval = fval
            else:
                lval = fval
                rval = cval

            op = getattr(operator, self.operators[clause['operator']])
            return op(lval, rval)

    # match_policies
    def include_any(self, target):
        for clause in self.filter['clauses']:
            if self.evaluate_clause(clause, target):
                return True
        return False

    def include_all(self, target):
        for clause in self.filter['clauses']:
            if not self.evaluate_clause(clause, target):
                return False
        return True

    def exclude_all(self, target):
        for clause in self.filter['clauses']:
            if not self.evaluate_clause(clause, target):
                return True
        return False

    def exclude_any(self, target):
        for clause in self.filter['clauses']:
            if self.evaluate_clause(clause, target):
                return False
        return True

    def match(self, target, action=None):
        if not action or action == 'past' or action in self.filter['actions']:
            if len(self.filter['clauses']) > 0:
                return getattr(self, self.filter['match_policy'])(target)
            else:
                return True
        else:
            return False


class StreamerSession(Session):
    client_id = None
    filter = None

    def on_open(self):
        transaction.commit()  # Release the database transaction

    def send_annotations(self):
        request = self.request
        registry = request.registry
        store = registry.queryUtility(interfaces.IStoreClass)(request)
        annotations = store.search_raw(self.query.query)
        self.received = len(annotations)

        # Can send zero to indicate that no past data is matched
        packet = {
            'payload': annotations,
            'type': 'annotation-notification',
            'options': {
                'action': 'past',
            }
        }
        self.send(packet)

    def on_message(self, msg):
        transaction.begin()
        try:
            struct = json.loads(msg)
            msg_type = struct.get('messageType', 'filter')

            if msg_type == 'filter':
                payload = struct['filter']
                self.offsetFrom = 0

                # Let's try to validate the schema
                validate(payload, filter_schema)
                self.filter = FilterHandler(payload)

                # If past is given, send the annotations back.
                if payload.get('past_data', {}).get('load_past') != 'none':
                    self.query = FilterToElasticFilter(payload, self.request)
                    if 'size' in self.query.query:
                        self.offsetFrom = int(self.query.query['size'])
                    self.send_annotations()
            elif msg_type == 'more_hits':
                more_hits = struct.get('moreHits', 50)
                if 'size' in self.query.query:
                    self.query.query['from'] = self.offsetFrom
                    self.query.query['size'] = more_hits
                    self.send_annotations()
                    self.offsetFrom += self.received
            elif msg_type == 'client_id':
                self.client_id = struct.get('value')
        except:
            log.exception("Parsing filter: %s", msg)
            transaction.abort()
            self.close()
        else:
            transaction.commit()


@subscriber(events.AnnotationEvent)
def after_action(event):
    try:
        request = event.request
        client_id = request.headers.get('X-Client-Id')

        action = event.action
        if action == 'read':
            return

        annotation = event.annotation
        manager = request.get_sockjs_manager()
        for session in manager.active_sessions():
            if session.client_id == client_id:
                continue

            try:
                if not session.request.has_permission('read', annotation):
                    continue

                flt = session.filter
                if not (flt and flt.match(annotation, action)):
                    continue

                packet = {
                    'payload': [annotation],
                    'type': 'annotation-notification',
                    'options': {
                        'action': action,
                    },
                }

                session.send(packet)
            except:
                log.exception(
                    'Checking stream match:\n%s\n%s',
                    annotation,
                    session.filter
                )
    except:
        log.exception('Streaming event: %s', event)


def includeme(config):
    config.include('pyramid_sockjs')
    config.add_sockjs_route(prefix='__streamer__', session=StreamerSession)
    config.scan(__name__)
