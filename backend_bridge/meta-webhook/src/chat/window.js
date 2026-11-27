'use strict';

const MESSENGER_WINDOW_MS = 24 * 60 * 60 * 1000;

/**
 * Messenger standard messaging window check:
 * Freeform replies are only allowed within 24 hours of the customer's last inbound message.
 */
function canReplyFreeform(lastInboundAt, now = new Date()) {
  if (!lastInboundAt) return false;
  const inboundMs = lastInboundAt instanceof Date ? lastInboundAt.getTime() : Date.parse(String(lastInboundAt));
  const nowMs = now instanceof Date ? now.getTime() : Date.parse(String(now));
  if (!Number.isFinite(inboundMs) || !Number.isFinite(nowMs)) return false;
  const elapsedMs = nowMs - inboundMs;
  if (elapsedMs < 0) return false;
  return elapsedMs < MESSENGER_WINDOW_MS;
}

module.exports = {
  MESSENGER_WINDOW_MS,
  canReplyFreeform,
};
