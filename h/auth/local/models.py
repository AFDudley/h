# -*- coding: utf-8 -*-
from functools import partial
import re
from uuid import uuid1, uuid4, UUID

from annotator import auth
from hem.interfaces import IDBSession
from hem.db import get_session
from horus.interfaces import (
    IActivationClass,
    IUserClass,
    IUIStrings,
)
from horus.models import (
    BaseModel,
    ActivationMixin,
    GroupMixin,
    UserMixin,
    UserGroupMixin,
)
from horus.strings import UIStringsBase
from pyramid_basemodel import Base, Session
from pyramid.threadlocal import get_current_request
from sqlalchemy import event, func, or_
from sqlalchemy.dialects import postgresql as pg
from sqlalchemy.schema import Column
from sqlalchemy.types import Integer, TypeDecorator, CHAR
import transaction

from h.interfaces import IConsumerClass


class GUID(TypeDecorator):
    """Platform-independent GUID type.

    From http://docs.sqlalchemy.org/en/latest/core/types.html
    Copyright (C) 2005-2011 the SQLAlchemy authors and contributors

    Uses Postgresql's UUID type, otherwise uses
    CHAR(32), storing as stringified hex values.

    """
    # pylint: disable=too-many-public-methods
    impl = CHAR

    def load_dialect_impl(self, dialect):
        if dialect.name == 'postgresql':
            return dialect.type_descriptor(pg.UUID())
        else:
            return dialect.type_descriptor(CHAR(32))

    def process_bind_param(self, value, dialect):
        if value is None:
            return value
        elif dialect.name == 'postgresql':
            return str(value)
        else:
            if not isinstance(value, UUID):
                return "%.32x" % UUID(value)
            else:
                # hexstring
                return "%.32x" % value

    def process_result_value(self, value, dialect):
        if value is None:
            return value
        else:
            return UUID(value)

    def python_type(self):
        return UUID


class Activation(ActivationMixin, Base):
    def __init__(self, *args, **kwargs):
        super(Activation, self).__init__(*args, **kwargs)

        # XXX: Horus currently has a bug where the Activation model isn't
        # flushed before the email is generated, causing the link to be
        # broken (hypothesis/h#1156).
        #
        # Fixed in horus@90f838cef12be249a9e9deb5f38b37151649e801
        request = get_current_request()
        db = get_session(request)
        db.add(self)
        db.flush()


class ConsumerMixin(BaseModel):
    """
    API Consumer

    The annotator-store :py:class:`annotator.auth.Authenticator` uses this
    function in the process of authenticating requests to verify the secrets of
    the JSON Web Token passed by the consumer client.

    """

    key = Column(GUID, default=partial(uuid1, clock_seq=id(Base)), index=True)
    secret = Column(GUID, default=uuid4)
    ttl = Column(Integer, default=auth.DEFAULT_TTL)

    def __init__(self, **kwargs):
        super(ConsumerMixin, self).__init__()
        self.__dict__.update(kwargs)

    def __repr__(self):
        return '<Consumer %r>' % self.key

    @classmethod
    def get_by_key(cls, request, key):
        return get_session(request).query(cls).filter(cls.key == key).first()

    @property
    def client_id(self):
        return unicode(self.key)

    @property
    def client_secret(self):
        return unicode(self.secret)


class Consumer(ConsumerMixin, Base):
    pass


class Group(GroupMixin, Base):
    pass


class User(UserMixin, Base):
    # pylint: disable=too-many-public-methods

    @classmethod
    def get_by_id(cls, request, userid):
        match = re.match(r'acct:([^@]+)@{}'.format(request.domain), userid)
        if match:
            return cls.get_by_username(request, match.group(1))
        else:
            return super(User, cls).get_by_id(request, userid)

    @classmethod
    def get_by_username(cls, request, username):
        session = get_session(request)

        lhs = func.replace(cls.username, '.', '')
        rhs = username.replace('.', '')
        return session.query(cls).filter(
            func.lower(lhs) == rhs.lower()
        ).first()

    @classmethod
    def get_by_username_or_email(cls, request, username, email):
        session = get_session(request)

        lhs = func.replace(cls.username, '.', '')
        rhs = username.replace('.', '')
        return session.query(cls).filter(
            or_(
                func.lower(lhs) == rhs.lower(),
                cls.email == email
            )
        ).first()

    @property
    def email_confirmed(self):
        return bool((self.status or 0) & 0b001)

    @email_confirmed.setter
    def email_confirmed(self, value):
        if value:
            self.status = (self.status or 0) | 0b001
        else:
            self.status = (self.status or 0) & ~0b001

    @property
    def optout(self):
        return bool((self.status or 0) & 0b010)

    @optout.setter
    def optout(self, value):
        if value:
            self.status = (self.status or 0) | 0b010
        else:
            self.status = (self.status or 0) & ~0b010

    @property
    def subscriptions(self):
        return bool((self.status or 0) & 0b100)

    @subscriptions.setter
    def subscriptions(self, value):
        if value:
            self.status = (self.status or 0) | 0b100
        else:
            self.status = (self.status or 0) & ~0b100


class UserGroup(UserGroupMixin, Base):
    pass


def create_event_listeners(config):
    settings = config.registry.settings

    # The sqlalchemy table object is created magically at runtime
    table = Consumer.__table__  # pylint: disable=no-member

    @event.listens_for(table, 'after_create')
    def create_api_consumer(target, connection, **kwargs):
        key = settings['api.key']
        secret = settings.get('api.secret')
        ttl = settings.get('api.ttl', auth.DEFAULT_TTL)

        session = Session()
        consumer = session.query(Consumer).filter(Consumer.key == key).first()
        if not consumer:
            with transaction.manager:
                consumer = Consumer(key=key, secret=secret, ttl=ttl)
                session.add(consumer)
                session.flush()


def includeme(config):
    registry = config.registry

    models = [
        (IActivationClass, Activation),
        (IUserClass, User),
        (IUIStrings, UIStringsBase),
        (IConsumerClass, Consumer),
        (IDBSession, Session)
    ]

    for iface, imp in models:
        if not registry.queryUtility(iface):
            registry.registerUtility(imp, iface)

    create_event_listeners(config)
