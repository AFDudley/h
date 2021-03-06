# -*- coding: utf-8 -*-

"""Defines unit tests for h.api."""

from mock import patch, MagicMock
from pytest import fixture, raises
from pyramid.testing import DummyRequest, DummyResource

from h import api

from helpers import DictMock


@fixture(autouse=True)
def replace_io(monkeypatch):
    """For all tests, mock paths to the "outside" world"""
    Annotation = DictMock()
    _trigger_event = MagicMock()
    _api_error = MagicMock()
    monkeypatch.setattr(api, 'Annotation', Annotation)
    monkeypatch.setattr(api, '_trigger_event', _trigger_event)
    monkeypatch.setattr(api, '_api_error', _api_error)


@fixture()
def user(monkeypatch):
    """Provide a mock user"""
    user = MagicMock()
    user.id = 'alice'
    user.consumer.key = 'consumer_key'

    # Make api.get_user() return our alice
    get_user = MagicMock()
    get_user.return_value = user
    monkeypatch.setattr(api, 'get_user', get_user)
    return user


def test_index():
    """Get the API descriptor"""

    result = api.index(DummyResource(), DummyRequest())

    # Pyramid's host url defaults to http://example.com
    host = 'http://example.com'
    links = result['links']
    assert links['annotation']['create']['method'] == 'POST'
    assert links['annotation']['create']['url'] == host + '/annotations'
    assert links['annotation']['delete']['method'] == 'DELETE'
    assert links['annotation']['delete']['url'] == host + '/annotations/:id'
    assert links['annotation']['read']['method'] == 'GET'
    assert links['annotation']['read']['url'] == host + '/annotations/:id'
    assert links['annotation']['update']['method'] == 'PUT'
    assert links['annotation']['update']['url'] == host + '/annotations/:id'
    assert links['search']['method'] == 'GET'
    assert links['search']['url'] == host + '/search'


def test_search_parameters():
    request_params = {
        'offset': '3',
        'limit': '100',
        'uri': 'http://bla.test',
        'some_field': 'something',
    }
    user = object()
    assert api._search_params(request_params, user=user) == {
        'query': {
            'uri': 'http://bla.test',
            'some_field': 'something',
        },
        'offset': 3,
        'limit': 100,
        'user': user,
    }


def test_bad_search_parameters():
    request_params = {
        'offset': '3foo',
        'limit': '\' drop table annotations',
    }
    user = object()
    assert api._search_params(request_params, user=user) == {
        'query': {},
        'user': user,
    }


@patch('h.api._create_annotation')
def test_create(mock_create_annotation, user):
    request = DummyRequest(json_body=_new_annotation)

    annotation = api.create(DummyResource, request)

    api._create_annotation.assert_called_once_with(_new_annotation, user)
    assert annotation == api._create_annotation.return_value
    _assert_event_triggered('create')


def test_create_annotation(user):
    annotation = api._create_annotation(_new_annotation, user)
    assert annotation['text'] == 'blabla'
    assert annotation['user'] == 'alice'
    assert annotation['consumer'] == 'consumer_key'
    assert annotation['permissions'] == _new_annotation['permissions']
    annotation.save.assert_called_once()


def test_read():
    annotation = DummyResource()

    result = api.read(annotation, DummyRequest())

    _assert_event_triggered('read')
    assert result == annotation, "Annotation should have been returned"


@patch('h.api._update_annotation')
def test_update(mock_update_annotation):
    annotation = api.Annotation(_old_annotation)
    request = DummyRequest(json_body=_new_annotation)
    request.has_permission = MagicMock(return_value=True)

    result = api.update(annotation, request)

    api._update_annotation.assert_called_once_with(annotation,
                                                   _new_annotation,
                                                   True)
    _assert_event_triggered('update')
    assert result is annotation, "Annotation should have been returned"


def test_update_annotation(user):
    annotation = api.Annotation(_old_annotation)

    api._update_annotation(annotation, _new_annotation, True)

    assert annotation['text'] == 'blabla'
    assert annotation['quote'] == 'original_quote'
    assert annotation['user'] == 'alice'
    assert annotation['consumer'] == 'consumer_key'
    assert annotation['permissions'] == _new_annotation['permissions']
    annotation.save.assert_called_once()


@patch('h.api._anonymize_deletes')
def test_update_anonymize_deletes(mock_anonymize_deletes):
    annotation = api.Annotation(_old_annotation)
    annotation['deleted'] = True
    request = DummyRequest(json_body=_new_annotation)

    api.update(annotation, request)

    api._anonymize_deletes.assert_called_once_with(annotation)


def test_anonymize_deletes():
    annotation = api.Annotation(_old_annotation)
    annotation['deleted'] = True

    api._anonymize_deletes(annotation)

    assert 'user' not in annotation
    assert annotation['permissions'] == {
        'admin': [],
        'update': ['bob'],
        'read': ['group:__world__'],
        'delete': [],
    }


def test_update_change_permissions_disallowed():
    annotation = api.Annotation(_old_annotation)

    with raises(RuntimeError):
        api._update_annotation(annotation, _new_annotation, False)

    assert annotation['text'] == 'old_text'
    assert annotation.save.call_count == 0


def test_delete():
    annotation = api.Annotation(_old_annotation)

    result = api.delete(annotation, DummyRequest())

    assert annotation.delete.assert_called_once()
    _assert_event_triggered('delete')
    assert result == {'id': '1234', 'deleted': True}, "Deletion confirmation should have been returned"


def _assert_event_triggered(action):
    assert api._trigger_event.call_count == 1, "Annotation event should have occured"
    assert api._trigger_event.call_args[0][2] == action, "Annotation event action should be " % action


_new_annotation = {
    'text': 'blabla',
    'created': '2040-05-20',
    'updated': '2040-05-23',
    'user': 'eve',
    'consumer': 'fake_consumer',
    'id': '1337',
    'permissions': {
        'admin': ['alice'],
        'update': ['alice'],
        'read': ['alice', 'group:__world__'],
        'delete': ['alice'],
    },
}

_old_annotation = {
    'text': 'old_text',
    'quote': 'original_quote',
    'created': '2010-01-01',
    'updated': '2010-01-02',
    'user': 'alice',
    'consumer': 'consumer_key',
    'id': '1234',
    'permissions': {
        'admin': ['alice'],
        'update': ['alice', 'bob'],
        'read': ['alice', 'group:__world__'],
        'delete': ['alice'],
    },
}
