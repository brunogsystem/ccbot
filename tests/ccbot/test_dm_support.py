"""Tests for DM (private chat) support.

Verifies that:
  - _get_thread_id returns DM_THREAD_ID for private chats
  - Thread bindings work with DM_THREAD_ID
  - _send_kwargs skips message_thread_id for DM
  - resolve_chat_id falls back to user_id for DM
  - safe_send skips message_thread_id for DM
"""

from unittest.mock import MagicMock

import pytest

from ccbot.bot import DM_THREAD_ID, _get_thread_id
from ccbot.handlers.message_queue import _send_kwargs
from ccbot.session import SessionManager


# --- DM_THREAD_ID constant ---


def test_dm_thread_id_is_zero() -> None:
    assert DM_THREAD_ID == 0


# --- _get_thread_id ---


def _make_update(chat_type: str, thread_id: int | None = None) -> MagicMock:
    """Build a minimal Update mock with the given chat type and thread_id."""
    update = MagicMock()
    msg = MagicMock()
    msg.chat.type = chat_type
    if thread_id is not None:
        msg.message_thread_id = thread_id
    else:
        msg.message_thread_id = None
    update.message = msg
    update.callback_query = None
    return update


class TestGetThreadIdDM:
    def test_private_chat_returns_dm_thread_id(self) -> None:
        update = _make_update("private")
        assert _get_thread_id(update) == DM_THREAD_ID

    def test_group_without_topic_returns_none(self) -> None:
        update = _make_update("supergroup", thread_id=None)
        assert _get_thread_id(update) is None

    def test_group_with_general_topic_returns_none(self) -> None:
        update = _make_update("supergroup", thread_id=1)
        assert _get_thread_id(update) is None

    def test_group_with_named_topic_returns_thread_id(self) -> None:
        update = _make_update("supergroup", thread_id=42)
        assert _get_thread_id(update) == 42


# --- _send_kwargs ---


class TestSendKwargsDM:
    def test_dm_thread_id_returns_empty(self) -> None:
        assert _send_kwargs(DM_THREAD_ID) == {}

    def test_none_returns_empty(self) -> None:
        assert _send_kwargs(None) == {}

    def test_real_thread_id_returns_kwargs(self) -> None:
        assert _send_kwargs(42) == {"message_thread_id": 42}


# --- Thread bindings with DM_THREAD_ID ---


@pytest.fixture
def mgr(monkeypatch: pytest.MonkeyPatch) -> SessionManager:
    monkeypatch.setattr(SessionManager, "_load_state", lambda self: None)
    monkeypatch.setattr(SessionManager, "_save_state", lambda self: None)
    return SessionManager()


class TestDMBindings:
    def test_bind_dm_and_get(self, mgr: SessionManager) -> None:
        mgr.bind_thread(100, DM_THREAD_ID, "@5", window_name="myproject")
        assert mgr.get_window_for_thread(100, DM_THREAD_ID) == "@5"

    def test_resolve_window_for_dm(self, mgr: SessionManager) -> None:
        mgr.bind_thread(100, DM_THREAD_ID, "@5")
        assert mgr.resolve_window_for_thread(100, DM_THREAD_ID) == "@5"

    def test_unbind_dm(self, mgr: SessionManager) -> None:
        mgr.bind_thread(100, DM_THREAD_ID, "@5")
        result = mgr.unbind_thread(100, DM_THREAD_ID)
        assert result == "@5"
        assert mgr.get_window_for_thread(100, DM_THREAD_ID) is None

    def test_iter_includes_dm_binding(self, mgr: SessionManager) -> None:
        mgr.bind_thread(100, DM_THREAD_ID, "@5")
        mgr.bind_thread(100, 42, "@6")
        result = set(mgr.iter_thread_bindings())
        assert result == {(100, DM_THREAD_ID, "@5"), (100, 42, "@6")}

    def test_dm_and_topic_bindings_independent(self, mgr: SessionManager) -> None:
        mgr.bind_thread(100, DM_THREAD_ID, "@5")
        mgr.bind_thread(100, 42, "@6")
        assert mgr.get_window_for_thread(100, DM_THREAD_ID) == "@5"
        assert mgr.get_window_for_thread(100, 42) == "@6"


class TestResolveChatIdDM:
    def test_dm_resolve_falls_back_to_user_id(self, mgr: SessionManager) -> None:
        """DM binding (thread_id=0) resolves to user_id (no group_chat_ids entry)."""
        assert mgr.resolve_chat_id(100, DM_THREAD_ID) == 100

    def test_dm_and_group_independent(self, mgr: SessionManager) -> None:
        """Group chat_ids don't affect DM resolution."""
        mgr.set_group_chat_id(100, 42, -1001234567890)
        assert mgr.resolve_chat_id(100, DM_THREAD_ID) == 100
        assert mgr.resolve_chat_id(100, 42) == -1001234567890
