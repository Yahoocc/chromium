import json
import itertools
import urllib.request
import websocket

targets = json.load(
    urllib.request.urlopen("http://127.0.0.1:9222/json")
)

page = next(x for x in targets if x["type"] == "page")
ws = websocket.create_connection(page["webSocketDebuggerUrl"])

counter = itertools.count(1)

def call(method, params=None):
    msg_id = next(counter)
    ws.send(json.dumps({
        "id": msg_id,
        "method": method,
        "params": params or {}
    }))

    while True:
        result = json.loads(ws.recv())
        if result.get("id") == msg_id:
            return result

call("Page.enable")

print(call("Page.navigate", {
    "url": "data:text/html,<h1>cdp-ok</h1>"
}))

while True:
    event = json.loads(ws.recv())
    if event.get("method") == "Page.loadEventFired":
        break

result = call("Runtime.evaluate", {
    "expression": "document.documentElement.outerHTML",
    "returnByValue": True
})

print(result["result"]["result"]["value"])
ws.close()

