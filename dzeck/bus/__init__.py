"""Message bus module for decoupled channel-agent communication."""

from dzeck.bus.events import InboundMessage, OutboundMessage
from dzeck.bus.queue import MessageBus

__all__ = ["MessageBus", "InboundMessage", "OutboundMessage"]
