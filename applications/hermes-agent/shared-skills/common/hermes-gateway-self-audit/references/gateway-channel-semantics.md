# Gateway and Discord State Semantics

A correct audit keeps the following evidence distinct:

1. unit configured and enabled;
2. process running;
3. gateway startup completed;
4. Discord/websocket connected;
5. bot authenticated;
6. user/channel authorization accepted;
7. incoming message observed;
8. response generated;
9. response delivered in the expected channel or thread.

A failure at one layer does not prove failure at every layer. Conversely, an
active process proves only process health. For auto-thread behavior, inspect the
configured mode, the triggering message type, thread creation/reuse event, and
actual response destination. Use IDs only as locally selected evidence and avoid
copying them into shared artifacts or reports unless necessary.
