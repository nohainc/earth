import test from 'node:test';
import assert from 'node:assert/strict';

class EventBroadcaster {
  constructor() {
    this.sseControllers = new Set();
    this.sockets = new Set();
  }

  addSocket(ws) {
    this.sockets.add(ws);
  }

  addSseController(controller) {
    this.sseControllers.add(controller);
  }

  broadcast(event) {
    const message = JSON.stringify(event);
    for (const ws of this.sockets) {
      try {
        ws.send(message);
      } catch {
        this.sockets.delete(ws);
      }
    }
    const encoder = new TextEncoder();
    const chunk = encoder.encode(`data: ${message}\n\n`);
    for (const controller of this.sseControllers) {
      try {
        controller.enqueue(chunk);
      } catch {
        this.sseControllers.delete(controller);
      }
    }
  }
}

test('SSE event stream delivers structured outbox events with data framing', async () => {
  const broadcaster = new EventBroadcaster();
  const chunks = [];
  let streamController;
  const stream = new ReadableStream({
    start(controller) {
      streamController = controller;
      broadcaster.addSseController(controller);
    },
    cancel() {
      broadcaster.sseControllers.delete(streamController);
    },
  });

  const reader = stream.getReader();

  broadcaster.broadcast({
    type: 'market_settlement',
    eventKey: 'trade:101',
    topic: 'world_activity',
    clearingPrice: 120.5,
  });

  const { value } = await reader.read();
  const text = new TextDecoder().decode(value);
  assert.match(text, /^data: /);
  assert.match(text, /\n\n$/);
  const parsed = JSON.parse(text.replace(/^data:\s*/, '').trim());
  assert.equal(parsed.eventKey, 'trade:101');
  assert.equal(parsed.clearingPrice, 120.5);

  reader.cancel();
});

test('Broadcaster sends identical payload to both SSE and WebSocket subscribers', async () => {
  const broadcaster = new EventBroadcaster();
  const wsMessages = [];
  const sseMessages = [];

  broadcaster.addSocket({
    send: (msg) => wsMessages.push(JSON.parse(msg)),
  });

  let controllerRef;
  const stream = new ReadableStream({
    start(controller) {
      controllerRef = controller;
      broadcaster.addSseController(controller);
    },
  });
  const reader = stream.getReader();

  const payload = {
    type: 'world_day_started',
    gameDay: 190,
    eventKey: 'day:190',
  };

  broadcaster.broadcast(payload);

  assert.equal(wsMessages.length, 1);
  assert.deepEqual(wsMessages[0], payload);

  const { value } = await reader.read();
  const sseText = new TextDecoder().decode(value);
  const sseParsed = JSON.parse(sseText.replace(/^data:\s*/, '').trim());
  assert.deepEqual(sseParsed, payload);

  reader.cancel();
});
