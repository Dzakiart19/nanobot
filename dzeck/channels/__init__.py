"""Chat channels module with plugin architecture."""

from dzeck.channels.base import BaseChannel
from dzeck.channels.manager import ChannelManager

__all__ = ["BaseChannel", "ChannelManager"]
