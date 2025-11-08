# Streaming HTTP Design Plan

This document outlines the changes needed to convert the agent service from simple HTTP POST to streaming HTTP using Server-Sent Events (SSE).

## Overview

Currently, the agent service waits for complete responses before returning results. Streaming will provide real-time updates as Claude generates text and executes tools.

## 1. Bedrock API Changes

**Location:** `agent-service/app.py:147`

### Current Implementation
```python
response = bedrock.converse(
    modelId=self.model_id,
    messages=messages,
    toolConfig={...}
)
```

### Streaming Implementation
```python
response = bedrock.converse_stream(
    modelId=self.model_id,
    messages=messages,
    toolConfig={...}
)
```

### Event Stream Handling

Parse the following Bedrock streaming events:

- **`messageStart`** - Begin processing message
- **`contentBlockStart`** - Start of text or tool use block
- **`contentBlockDelta`** - Incremental text chunks or tool input fragments
- **`contentBlockStop`** - End of content block
- **`messageStop`** - Complete response with `stopReason`

### Example Event Processing
```python
stream = response.get('stream')
for event in stream:
    if 'contentBlockDelta' in event:
        delta = event['contentBlockDelta']['delta']
        if 'text' in delta:
            # Stream text chunk to client
            yield {"type": "text_delta", "text": delta['text']}
    elif 'messageStop' in event:
        stop_reason = event['messageStop']['stopReason']
        # Handle completion
```

## 2. FastAPI Endpoint Changes

**Location:** `agent-service/app.py:274`

### Current Implementation
```python
@app.post("/agent/run", response_model=AgentResponse)
async def run_agent(request: AgentRequest):
    agent = BedrockAgent(BEDROCK_MODEL_ID)
    result = await agent.run(request.message, request.max_turns)
    return result  # Single JSON response
```

### Streaming Implementation
```python
from fastapi.responses import StreamingResponse

@app.post("/agent/stream")
async def stream_agent(request: AgentRequest):
    async def event_generator():
        agent = BedrockAgent(BEDROCK_MODEL_ID)
        async for event in agent.run_stream(request.message, request.max_turns):
            # Yield Server-Sent Events format
            yield f"data: {json.dumps(event)}\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no"
        }
    )
```

### Event Types to Stream

**Text Deltas:**
```json
{"type": "text_delta", "text": "incremental text chunk"}
```

**Tool Use Start:**
```json
{"type": "tool_use_start", "tool": "calculator", "id": "tooluse_abc123"}
```

**Tool Use Input (as it streams):**
```json
{"type": "tool_input_delta", "delta": "{\"number\":", "id": "tooluse_abc123"}
```

**Tool Execution:**
```json
{"type": "tool_executing", "tool": "calculator", "id": "tooluse_abc123"}
```

**Tool Result:**
```json
{"type": "tool_result", "tool": "calculator", "result": "12", "id": "tooluse_abc123"}
```

**Completion:**
```json
{"type": "done", "turns": 2, "tool_calls": [...]}
```

**Error:**
```json
{"type": "error", "error": "error message", "turns": 1}
```

## 3. Agent Loop Changes

**Location:** `agent-service/app.py:127-243`

### New Method: `run_stream()`

Replace the synchronous `run()` method with an async generator:

```python
async def run_stream(self, user_message: str, max_turns: int = 10):
    """Run the agent loop with streaming"""
    messages = [
        {
            "role": "user",
            "content": [{"text": user_message}]
        }
    ]

    tools = await mcp_client.fetch_all_tools()
    tool_calls_log = []
    turns = 0

    while turns < max_turns:
        turns += 1

        try:
            # Call Bedrock with streaming
            response = bedrock.converse_stream(
                modelId=self.model_id,
                messages=messages,
                toolConfig={"tools": tools, "toolChoice": {"auto": {}}} if tools else None
            )

            # Process stream
            stream = response.get('stream')
            current_message = {"role": "assistant", "content": []}
            current_text = ""
            current_tool_uses = {}

            for event in stream:
                if 'contentBlockStart' in event:
                    # Handle start of text or tool block
                    pass

                elif 'contentBlockDelta' in event:
                    delta = event['contentBlockDelta']['delta']

                    if 'text' in delta:
                        # Stream text immediately
                        current_text += delta['text']
                        yield {"type": "text_delta", "text": delta['text']}

                    elif 'toolUse' in delta:
                        # Accumulate tool input
                        # Could stream tool input deltas if desired
                        pass

                elif 'contentBlockStop' in event:
                    # Block completed
                    pass

                elif 'messageStop' in event:
                    stop_reason = event['messageStop']['stopReason']

                    if stop_reason == "end_turn":
                        yield {
                            "type": "done",
                            "turns": turns,
                            "tool_calls": tool_calls_log
                        }
                        return

                    elif stop_reason == "tool_use":
                        # Execute tools and continue
                        # (See tool execution section below)
                        break

        except Exception as e:
            yield {"type": "error", "error": str(e), "turns": turns}
            return
```

### Tool Execution in Stream

When `stopReason == "tool_use"`:

1. Yield tool use start events
2. Execute tools synchronously (MCP calls)
3. Yield tool result events
4. Add tool results to messages
5. Continue loop for next turn

```python
# After detecting tool_use stopReason
for content_block in current_message["content"]:
    if "toolUse" in content_block:
        tool_use = content_block["toolUse"]

        # Notify client tool is executing
        yield {
            "type": "tool_executing",
            "tool": tool_use["name"],
            "id": tool_use["toolUseId"]
        }

        # Execute synchronously
        result = await mcp_client.execute_tool(
            tool_use["name"],
            tool_use["input"]
        )

        # Notify client of result
        yield {
            "type": "tool_result",
            "tool": tool_use["name"],
            "result": result,
            "id": tool_use["toolUseId"]
        }

        # Add to log
        tool_calls_log.append({
            "tool": tool_use["name"],
            "input": tool_use["input"],
            "tool_use_id": tool_use["toolUseId"]
        })
```

## 4. MCP Client Changes

**Location:** `agent-service/app.py:89-115`

### No Changes Required

MCP tool execution remains synchronous:
- Tools execute as blocking calls
- Complete results returned
- No streaming at MCP layer

**Rationale:**
- Most tools (filesystem, calculator) complete quickly
- Streaming tool execution adds complexity without benefit
- Client still gets real-time updates via tool execution events

## 5. Client Changes

### Current Client Usage
```bash
curl -X POST http://localhost:8000/agent/run \
  -H "Content-Type: application/json" \
  -d '{"message": "What is the square root of 144?"}'

# Response (single JSON)
{"response":"12","turns":2,"tool_calls":[...]}
```

### Streaming Client Usage
```bash
curl -X POST http://localhost:8000/agent/stream \
  -H "Content-Type: application/json" \
  -d '{"message": "What is the square root of 144?"}' \
  --no-buffer
```

### Expected Stream Output
```
data: {"type":"tool_use_start","tool":"sqrt","id":"tooluse_abc"}

data: {"type":"tool_executing","tool":"sqrt","id":"tooluse_abc"}

data: {"type":"tool_result","tool":"sqrt","result":"12","id":"tooluse_abc"}

data: {"type":"text_delta","text":"The"}

data: {"type":"text_delta","text":" square"}

data: {"type":"text_delta","text":" root"}

data: {"type":"text_delta","text":" of"}

data: {"type":"text_delta","text":" 144"}

data: {"type":"text_delta","text":" is"}

data: {"type":"text_delta","text":" 12"}

data: {"type":"text_delta","text":"."}

data: {"type":"done","turns":2,"tool_calls":[...]}
```

### JavaScript Client Example
```javascript
const response = await fetch('http://localhost:8000/agent/stream', {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({message: 'What is the square root of 144?'})
});

const reader = response.body.getReader();
const decoder = new TextDecoder();

while (true) {
  const {done, value} = await reader.read();
  if (done) break;

  const chunk = decoder.decode(value);
  const lines = chunk.split('\n');

  for (const line of lines) {
    if (line.startsWith('data: ')) {
      const event = JSON.parse(line.slice(6));

      if (event.type === 'text_delta') {
        process.stdout.write(event.text);
      } else if (event.type === 'tool_result') {
        console.log(`\n[Tool ${event.tool} → ${event.result}]`);
      } else if (event.type === 'done') {
        console.log('\n\nCompleted in', event.turns, 'turns');
      }
    }
  }
}
```

## 6. Error Handling

### Stream Interruption
```python
try:
    for event in stream:
        # Process event
        yield event_data
except ClientError as e:
    yield {
        "type": "error",
        "error": f"Bedrock API error: {e.response['Error']['Message']}",
        "turns": turns
    }
except Exception as e:
    yield {
        "type": "error",
        "error": str(e),
        "turns": turns
    }
```

### Client Disconnection
FastAPI automatically handles client disconnection. The generator will stop when the client closes the connection.

## Benefits

1. **Real-time feedback** - Users see responses as they're generated
2. **Better UX** - No waiting for complete response
3. **Tool visibility** - See tools executing in real-time
4. **Progressive rendering** - Client can display partial responses
5. **Lower perceived latency** - First byte arrives quickly

## Tradeoffs

1. **Complexity** - More complex error handling and state management
2. **Debugging** - Harder to debug partial states
3. **Client changes** - Clients must handle SSE instead of simple JSON
4. **Buffering issues** - Need proper headers to prevent proxy buffering
5. **Reconnection** - No built-in resume capability (entire conversation restarts)

## Step-by-Step Implementation Guide

### Step 1: Set Up Test Infrastructure

**Goal:** Create comprehensive test suite before implementation

**Files to create:**
- `agent-service/tests/__init__.py`
- `agent-service/tests/test_streaming.py`
- `agent-service/tests/conftest.py`
- `agent-service/tests/mock_bedrock.py`

**Actions:**

1.1. Create test directory structure:
```bash
mkdir -p agent-service/tests
touch agent-service/tests/__init__.py
```

1.2. Add test dependencies to `agent-service/requirements.txt`:
```text
pytest>=7.4.0
pytest-asyncio>=0.21.0
pytest-mock>=3.11.0
httpx>=0.24.0
```

1.3. Create `agent-service/tests/conftest.py`:
```python
import pytest
from unittest.mock import AsyncMock, MagicMock
from fastapi.testclient import TestClient
import sys
import os

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from app import app, mcp_client, bedrock

@pytest.fixture
def client():
    """Test client for FastAPI app"""
    return TestClient(app)

@pytest.fixture
def mock_bedrock():
    """Mock Bedrock client"""
    return MagicMock()

@pytest.fixture
def mock_mcp_client():
    """Mock MCP client"""
    mock = AsyncMock()
    mock.fetch_all_tools = AsyncMock(return_value=[])
    mock.execute_tool = AsyncMock(return_value='{"result": "42"}')
    return mock

@pytest.fixture(autouse=True)
def reset_mcp_cache():
    """Reset MCP client cache before each test"""
    mcp_client.tools_cache = None
    mcp_client.tool_to_server = {}
```

1.4. Create `agent-service/tests/mock_bedrock.py`:
```python
"""Mock Bedrock streaming responses for testing"""

def mock_text_only_stream():
    """Mock stream with only text (no tools)"""
    return {
        'stream': [
            {'messageStart': {'role': 'assistant'}},
            {'contentBlockStart': {'start': {'text': {}}, 'contentBlockIndex': 0}},
            {'contentBlockDelta': {'delta': {'text': 'Hello'}, 'contentBlockIndex': 0}},
            {'contentBlockDelta': {'delta': {'text': ' world'}, 'contentBlockIndex': 0}},
            {'contentBlockDelta': {'delta': {'text': '!'}, 'contentBlockIndex': 0}},
            {'contentBlockStop': {'contentBlockIndex': 0}},
            {'messageStop': {'stopReason': 'end_turn'}}
        ]
    }

def mock_tool_use_stream():
    """Mock stream with tool use"""
    return {
        'stream': [
            {'messageStart': {'role': 'assistant'}},
            {'contentBlockStart': {'start': {'toolUse': {'toolUseId': 'tool_1', 'name': 'sqrt'}}, 'contentBlockIndex': 0}},
            {'contentBlockDelta': {'delta': {'toolUse': {'input': '{"number":'}}, 'contentBlockIndex': 0}},
            {'contentBlockDelta': {'delta': {'toolUse': {'input': '144}'}}, 'contentBlockIndex': 0}},
            {'contentBlockStop': {'contentBlockIndex': 0}},
            {'messageStop': {'stopReason': 'tool_use'}}
        ]
    }

def mock_tool_response_stream():
    """Mock stream after tool execution"""
    return {
        'stream': [
            {'messageStart': {'role': 'assistant'}},
            {'contentBlockStart': {'start': {'text': {}}, 'contentBlockIndex': 0}},
            {'contentBlockDelta': {'delta': {'text': 'The answer is 12'}, 'contentBlockIndex': 0}},
            {'contentBlockStop': {'contentBlockIndex': 0}},
            {'messageStop': {'stopReason': 'end_turn'}}
        ]
    }

def mock_error_stream():
    """Mock stream that raises an error"""
    def error_generator():
        yield {'messageStart': {'role': 'assistant'}}
        raise Exception("Bedrock API error")

    return {'stream': error_generator()}

def mock_max_tokens_stream():
    """Mock stream that hits max tokens"""
    return {
        'stream': [
            {'messageStart': {'role': 'assistant'}},
            {'contentBlockStart': {'start': {'text': {}}, 'contentBlockIndex': 0}},
            {'contentBlockDelta': {'delta': {'text': 'Partial response'}, 'contentBlockIndex': 0}},
            {'contentBlockStop': {'contentBlockIndex': 0}},
            {'messageStop': {'stopReason': 'max_tokens'}}
        ]
    }
```

**Test this step:**
```bash
cd agent-service
pip install -r requirements.txt
pytest tests/ -v
```

**Expected output:** `collected 0 items` (no tests yet, but setup works)

---

### Step 2: Write Unit Tests for Bedrock Stream Parser

**Goal:** Test Bedrock event stream parsing in isolation

**File to create:** `agent-service/tests/test_bedrock_parser.py`

**Actions:**

2.1. Create parser unit tests:
```python
import pytest
from tests.mock_bedrock import (
    mock_text_only_stream,
    mock_tool_use_stream,
    mock_max_tokens_stream
)

@pytest.mark.asyncio
async def test_parse_text_only_stream():
    """Test parsing a text-only response stream"""
    from app import BedrockStreamParser

    stream = mock_text_only_stream()
    parser = BedrockStreamParser()

    events = []
    async for event in parser.parse(stream['stream']):
        events.append(event)

    # Should have text deltas and done event
    text_deltas = [e for e in events if e['type'] == 'text_delta']
    assert len(text_deltas) == 3
    assert text_deltas[0]['text'] == 'Hello'
    assert text_deltas[1]['text'] == ' world'
    assert text_deltas[2]['text'] == '!'

    done_events = [e for e in events if e['type'] == 'done']
    assert len(done_events) == 1
    assert done_events[0]['stop_reason'] == 'end_turn'

@pytest.mark.asyncio
async def test_parse_tool_use_stream():
    """Test parsing a tool use stream"""
    from app import BedrockStreamParser

    stream = mock_tool_use_stream()
    parser = BedrockStreamParser()

    events = []
    async for event in parser.parse(stream['stream']):
        events.append(event)

    # Should have tool use start and tool use detected
    tool_starts = [e for e in events if e['type'] == 'tool_use_start']
    assert len(tool_starts) == 1
    assert tool_starts[0]['tool'] == 'sqrt'
    assert tool_starts[0]['id'] == 'tool_1'

    tool_detected = [e for e in events if e['type'] == 'tool_use_detected']
    assert len(tool_detected) == 1
    assert tool_detected[0]['stop_reason'] == 'tool_use'

@pytest.mark.asyncio
async def test_parse_max_tokens_stream():
    """Test handling max_tokens stop reason"""
    from app import BedrockStreamParser

    stream = mock_max_tokens_stream()
    parser = BedrockStreamParser()

    events = []
    async for event in parser.parse(stream['stream']):
        events.append(event)

    done_events = [e for e in events if e['type'] == 'done']
    assert len(done_events) == 1
    assert done_events[0]['stop_reason'] == 'max_tokens'
    assert 'truncated' in done_events[0].get('message', '').lower() or done_events[0]['stop_reason'] == 'max_tokens'

@pytest.mark.asyncio
async def test_parse_stream_accumulates_message():
    """Test that parser correctly accumulates the full message"""
    from app import BedrockStreamParser

    stream = mock_text_only_stream()
    parser = BedrockStreamParser()

    async for event in parser.parse(stream['stream']):
        pass

    # Parser should have accumulated full message
    assert parser.current_message is not None
    assert parser.current_message['role'] == 'assistant'
```

**Test this step:**
```bash
pytest agent-service/tests/test_bedrock_parser.py -v
```

**Expected output:** All tests should FAIL (parser not implemented yet)

---

### Step 3: Implement Bedrock Stream Parser

**Goal:** Create a parser class to handle Bedrock streaming events

**File to modify:** `agent-service/app.py`

**Actions:**

3.1. Add `BedrockStreamParser` class to `app.py` (add after imports, before other classes):
```python
class BedrockStreamParser:
    """Parses Bedrock converse_stream events"""

    def __init__(self):
        self.current_message = None
        self.current_content_blocks = []
        self.current_block_index = None

    async def parse(self, stream):
        """Parse Bedrock stream events and yield normalized events"""
        self.current_message = {"role": "assistant", "content": []}
        self.current_content_blocks = []

        for event in stream:
            if 'messageStart' in event:
                self.current_message = {"role": event['messageStart']['role'], "content": []}

            elif 'contentBlockStart' in event:
                block_start = event['contentBlockStart']
                index = block_start['contentBlockIndex']

                # Initialize content block
                while len(self.current_content_blocks) <= index:
                    self.current_content_blocks.append(None)

                if 'toolUse' in block_start['start']:
                    tool_use = block_start['start']['toolUse']
                    self.current_content_blocks[index] = {
                        'toolUse': {
                            'toolUseId': tool_use['toolUseId'],
                            'name': tool_use['name'],
                            'input': ''
                        }
                    }
                    yield {
                        'type': 'tool_use_start',
                        'tool': tool_use['name'],
                        'id': tool_use['toolUseId']
                    }
                else:
                    self.current_content_blocks[index] = {'text': ''}

            elif 'contentBlockDelta' in event:
                delta_event = event['contentBlockDelta']
                index = delta_event['contentBlockIndex']
                delta = delta_event['delta']

                if 'text' in delta:
                    self.current_content_blocks[index]['text'] += delta['text']
                    yield {
                        'type': 'text_delta',
                        'text': delta['text']
                    }
                elif 'toolUse' in delta:
                    self.current_content_blocks[index]['toolUse']['input'] += delta['toolUse']['input']

            elif 'contentBlockStop' in event:
                index = event['contentBlockStop']['contentBlockIndex']
                if self.current_content_blocks[index] is not None:
                    self.current_message['content'].append(self.current_content_blocks[index])

            elif 'messageStop' in event:
                stop_reason = event['messageStop']['stopReason']

                if stop_reason == 'end_turn':
                    yield {
                        'type': 'done',
                        'stop_reason': 'end_turn',
                        'message': self.current_message
                    }
                elif stop_reason == 'tool_use':
                    yield {
                        'type': 'tool_use_detected',
                        'stop_reason': 'tool_use',
                        'message': self.current_message
                    }
                elif stop_reason == 'max_tokens':
                    yield {
                        'type': 'done',
                        'stop_reason': 'max_tokens',
                        'message': 'Response truncated due to max tokens'
                    }
                else:
                    yield {
                        'type': 'done',
                        'stop_reason': stop_reason,
                        'message': self.current_message
                    }
```

**Test this step:**
```bash
pytest agent-service/tests/test_bedrock_parser.py -v
```

**Expected output:** All parser tests should PASS

---

### Step 4: Write Unit Tests for Agent Streaming

**Goal:** Test the agent's streaming logic with mocked Bedrock

**File to create:** `agent-service/tests/test_agent_streaming.py`

**Actions:**

4.1. Create agent streaming tests:
```python
import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from tests.mock_bedrock import (
    mock_text_only_stream,
    mock_tool_use_stream,
    mock_tool_response_stream,
    mock_error_stream
)

@pytest.mark.asyncio
async def test_agent_stream_text_only(mock_mcp_client):
    """Test agent streaming with text-only response"""
    from app import BedrockAgent

    with patch('app.bedrock') as mock_bedrock:
        mock_bedrock.converse_stream.return_value = mock_text_only_stream()
        with patch('app.mcp_client', mock_mcp_client):
            agent = BedrockAgent("test-model-id")

            events = []
            async for event in agent.run_stream("Hello"):
                events.append(event)

            # Should have text deltas and done event
            text_deltas = [e for e in events if e['type'] == 'text_delta']
            assert len(text_deltas) > 0

            done_events = [e for e in events if e['type'] == 'done']
            assert len(done_events) == 1
            assert done_events[0]['turns'] == 1

@pytest.mark.asyncio
async def test_agent_stream_with_tool_use(mock_mcp_client):
    """Test agent streaming with tool use"""
    from app import BedrockAgent

    # Mock tool execution
    mock_mcp_client.execute_tool.return_value = '{"result": 12}'

    with patch('app.bedrock') as mock_bedrock:
        # First call returns tool use, second returns text response
        mock_bedrock.converse_stream.side_effect = [
            mock_tool_use_stream(),
            mock_tool_response_stream()
        ]

        with patch('app.mcp_client', mock_mcp_client):
            agent = BedrockAgent("test-model-id")

            events = []
            async for event in agent.run_stream("What is sqrt of 144?"):
                events.append(event)

            # Should have tool events
            tool_starts = [e for e in events if e['type'] == 'tool_use_start']
            assert len(tool_starts) == 1
            assert tool_starts[0]['tool'] == 'sqrt'

            tool_executing = [e for e in events if e['type'] == 'tool_executing']
            assert len(tool_executing) == 1

            tool_results = [e for e in events if e['type'] == 'tool_result']
            assert len(tool_results) == 1

            # Should have text from second turn
            text_deltas = [e for e in events if e['type'] == 'text_delta']
            assert len(text_deltas) > 0

            # Should complete after 2 turns
            done_events = [e for e in events if e['type'] == 'done']
            assert len(done_events) == 1
            assert done_events[0]['turns'] == 2

@pytest.mark.asyncio
async def test_agent_stream_max_turns(mock_mcp_client):
    """Test agent respects max_turns limit"""
    from app import BedrockAgent

    with patch('app.bedrock') as mock_bedrock:
        # Always return tool use to force max turns
        mock_bedrock.converse_stream.return_value = mock_tool_use_stream()

        with patch('app.mcp_client', mock_mcp_client):
            agent = BedrockAgent("test-model-id")

            events = []
            async for event in agent.run_stream("Test", max_turns=2):
                events.append(event)

            # Should stop at max turns
            done_events = [e for e in events if e['type'] == 'done']
            assert len(done_events) == 1
            # Either hits max_turns or completes within limit
            assert done_events[0]['turns'] <= 2

@pytest.mark.asyncio
async def test_agent_stream_error_handling(mock_mcp_client):
    """Test agent handles streaming errors gracefully"""
    from app import BedrockAgent
    from botocore.exceptions import ClientError

    with patch('app.bedrock') as mock_bedrock:
        # Simulate Bedrock error
        mock_bedrock.converse_stream.side_effect = ClientError(
            {'Error': {'Message': 'Test error'}},
            'converse_stream'
        )

        with patch('app.mcp_client', mock_mcp_client):
            agent = BedrockAgent("test-model-id")

            events = []
            async for event in agent.run_stream("Test"):
                events.append(event)

            # Should yield error event
            error_events = [e for e in events if e['type'] == 'error']
            assert len(error_events) == 1
            assert 'error' in error_events[0]['error'].lower()

@pytest.mark.asyncio
async def test_agent_stream_tool_execution_error(mock_mcp_client):
    """Test agent handles tool execution errors"""
    from app import BedrockAgent

    # Mock tool execution failure
    mock_mcp_client.execute_tool.side_effect = Exception("Tool execution failed")

    with patch('app.bedrock') as mock_bedrock:
        mock_bedrock.converse_stream.return_value = mock_tool_use_stream()

        with patch('app.mcp_client', mock_mcp_client):
            agent = BedrockAgent("test-model-id")

            events = []
            async for event in agent.run_stream("Test"):
                events.append(event)

            # Should yield error event or tool error result
            has_error = any(e['type'] in ['error', 'tool_result'] for e in events)
            assert has_error
```

**Test this step:**
```bash
pytest agent-service/tests/test_agent_streaming.py -v
```

**Expected output:** All tests should FAIL (streaming not implemented yet)

---

### Step 5: Implement Agent Streaming Method

**Goal:** Add `run_stream()` method to BedrockAgent class

**File to modify:** `agent-service/app.py`

**Actions:**

5.1. Add `run_stream()` method to `BedrockAgent` class (add after existing `run()` method):
```python
async def run_stream(self, user_message: str, max_turns: int = 10):
    """Run the agent loop with streaming events"""
    messages = [
        {
            "role": "user",
            "content": [{"text": user_message}]
        }
    ]

    # Fetch available tools
    tools = await mcp_client.fetch_all_tools()

    tool_calls_log = []
    turns = 0

    while turns < max_turns:
        turns += 1

        try:
            # Call Bedrock with streaming
            response = bedrock.converse_stream(
                modelId=self.model_id,
                messages=messages,
                toolConfig={
                    "tools": tools,
                    "toolChoice": {"auto": {}}
                } if tools else None
            )

            # Parse stream
            parser = BedrockStreamParser()
            stream = response.get('stream')

            tool_use_detected = False
            current_message = None

            async for event in parser.parse(stream):
                if event['type'] in ['text_delta', 'tool_use_start']:
                    # Stream these events immediately to client
                    yield event

                elif event['type'] == 'tool_use_detected':
                    tool_use_detected = True
                    current_message = event['message']

                elif event['type'] == 'done':
                    if event['stop_reason'] == 'end_turn':
                        yield {
                            "type": "done",
                            "turns": turns,
                            "tool_calls": tool_calls_log
                        }
                        return
                    elif event['stop_reason'] == 'max_tokens':
                        yield {
                            "type": "done",
                            "turns": turns,
                            "tool_calls": tool_calls_log,
                            "truncated": True
                        }
                        return

            # Handle tool use
            if tool_use_detected and current_message:
                messages.append(current_message)
                tool_results = []

                for content in current_message.get("content", []):
                    if "toolUse" in content:
                        tool_use = content["toolUse"]
                        tool_name = tool_use["name"]
                        tool_use_id = tool_use["toolUseId"]

                        # Parse tool input (may be JSON string)
                        try:
                            tool_input = json.loads(tool_use["input"]) if isinstance(tool_use["input"], str) else tool_use["input"]
                        except:
                            tool_input = tool_use["input"]

                        # Log tool call
                        tool_calls_log.append({
                            "tool": tool_name,
                            "input": tool_input,
                            "tool_use_id": tool_use_id
                        })

                        # Notify executing
                        yield {
                            "type": "tool_executing",
                            "tool": tool_name,
                            "id": tool_use_id
                        }

                        # Execute tool via MCP
                        try:
                            result = await mcp_client.execute_tool(tool_name, tool_input)
                        except Exception as e:
                            result = json.dumps({"error": f"Tool execution failed: {str(e)}"})

                        # Notify result
                        yield {
                            "type": "tool_result",
                            "tool": tool_name,
                            "result": result,
                            "id": tool_use_id
                        }

                        tool_results.append({
                            "toolResult": {
                                "toolUseId": tool_use_id,
                                "content": [{"text": result}]
                            }
                        })

                # Add tool results to conversation
                messages.append({
                    "role": "user",
                    "content": tool_results
                })

                # Continue to next turn
                continue

        except ClientError as e:
            error_message = f"Bedrock API error: {e.response['Error']['Message']}"
            yield {
                "type": "error",
                "error": error_message,
                "turns": turns
            }
            return

        except Exception as e:
            error_message = f"Agent error: {str(e)}"
            yield {
                "type": "error",
                "error": error_message,
                "turns": turns
            }
            return

    # Max turns reached
    yield {
        "type": "done",
        "turns": turns,
        "tool_calls": tool_calls_log,
        "max_turns_reached": True
    }
```

**Test this step:**
```bash
pytest agent-service/tests/test_agent_streaming.py -v
```

**Expected output:** All agent streaming tests should PASS

---

### Step 6: Write Integration Tests for FastAPI Endpoint

**Goal:** Test the HTTP streaming endpoint end-to-end

**File to create:** `agent-service/tests/test_endpoint_streaming.py`

**Actions:**

6.1. Create endpoint integration tests:
```python
import pytest
import json
from fastapi.testclient import TestClient
from unittest.mock import patch, AsyncMock
from tests.mock_bedrock import mock_text_only_stream, mock_tool_use_stream, mock_tool_response_stream

@pytest.fixture
def streaming_client():
    """Test client for streaming endpoints"""
    from app import app
    # Use TestClient without stream context for SSE testing
    return TestClient(app)

def test_stream_endpoint_exists(streaming_client):
    """Test that /agent/stream endpoint exists"""
    response = streaming_client.post(
        "/agent/stream",
        json={"message": "test"}
    )
    # Should not be 404
    assert response.status_code != 404

def test_stream_endpoint_content_type(mock_mcp_client):
    """Test that streaming endpoint returns SSE content type"""
    from app import app

    with patch('app.mcp_client', mock_mcp_client):
        with patch('app.bedrock') as mock_bedrock:
            mock_bedrock.converse_stream.return_value = mock_text_only_stream()

            client = TestClient(app)
            with client.stream("POST", "/agent/stream", json={"message": "test"}) as response:
                assert response.status_code == 200
                assert "text/event-stream" in response.headers.get("content-type", "")

def test_stream_endpoint_text_response(mock_mcp_client):
    """Test streaming endpoint with text-only response"""
    from app import app

    with patch('app.mcp_client', mock_mcp_client):
        with patch('app.bedrock') as mock_bedrock:
            mock_bedrock.converse_stream.return_value = mock_text_only_stream()

            client = TestClient(app)
            with client.stream("POST", "/agent/stream", json={"message": "Hello"}) as response:
                events = []
                for line in response.iter_lines():
                    if line.startswith("data: "):
                        event_data = json.loads(line[6:])
                        events.append(event_data)

                # Should have text deltas
                text_deltas = [e for e in events if e['type'] == 'text_delta']
                assert len(text_deltas) > 0

                # Should have done event
                done_events = [e for e in events if e['type'] == 'done']
                assert len(done_events) == 1

def test_stream_endpoint_tool_use(mock_mcp_client):
    """Test streaming endpoint with tool use"""
    from app import app

    mock_mcp_client.execute_tool.return_value = '{"result": 12}'

    with patch('app.mcp_client', mock_mcp_client):
        with patch('app.bedrock') as mock_bedrock:
            mock_bedrock.converse_stream.side_effect = [
                mock_tool_use_stream(),
                mock_tool_response_stream()
            ]

            client = TestClient(app)
            with client.stream("POST", "/agent/stream", json={"message": "sqrt 144"}) as response:
                events = []
                for line in response.iter_lines():
                    if line.startswith("data: "):
                        event_data = json.loads(line[6:])
                        events.append(event_data)

                # Should have tool events
                tool_starts = [e for e in events if e['type'] == 'tool_use_start']
                assert len(tool_starts) >= 1

                tool_results = [e for e in events if e['type'] == 'tool_result']
                assert len(tool_results) >= 1

def test_stream_endpoint_headers(mock_mcp_client):
    """Test streaming endpoint has correct headers"""
    from app import app

    with patch('app.mcp_client', mock_mcp_client):
        with patch('app.bedrock') as mock_bedrock:
            mock_bedrock.converse_stream.return_value = mock_text_only_stream()

            client = TestClient(app)
            with client.stream("POST", "/agent/stream", json={"message": "test"}) as response:
                headers = response.headers
                assert headers.get("cache-control") == "no-cache"
                assert headers.get("x-accel-buffering") == "no"

def test_stream_endpoint_malformed_request(streaming_client):
    """Test streaming endpoint with malformed request"""
    response = streaming_client.post(
        "/agent/stream",
        json={"invalid": "field"}
    )
    assert response.status_code == 422  # Validation error
```

**Test this step:**
```bash
pytest agent-service/tests/test_endpoint_streaming.py -v
```

**Expected output:** All tests should FAIL (endpoint not implemented yet)

---

### Step 7: Implement FastAPI Streaming Endpoint

**Goal:** Add `/agent/stream` endpoint to FastAPI app

**File to modify:** `agent-service/app.py`

**Actions:**

7.1. Add streaming endpoint (add after existing `/agent/run` endpoint):
```python
@app.post("/agent/stream")
async def stream_agent(request: AgentRequest):
    """Stream agent responses using Server-Sent Events"""
    async def event_generator():
        try:
            agent = BedrockAgent(BEDROCK_MODEL_ID)
            async for event in agent.run_stream(request.message, request.max_turns):
                # Yield SSE format: "data: {json}\n\n"
                yield f"data: {json.dumps(event)}\n\n"
        except Exception as e:
            # Yield error event
            error_event = {
                "type": "error",
                "error": str(e),
                "turns": 0
            }
            yield f"data: {json.dumps(error_event)}\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no"
        }
    )
```

7.2. Add import at top of file:
```python
from fastapi.responses import StreamingResponse
```

**Test this step:**
```bash
pytest agent-service/tests/test_endpoint_streaming.py -v
```

**Expected output:** All endpoint tests should PASS

---

### Step 8: Update Non-Streaming Endpoint for Backward Compatibility

**Goal:** Make existing `/agent/run` use new streaming internally

**File to modify:** `agent-service/app.py`

**Actions:**

8.1. Replace the existing `run_agent` function:
```python
@app.post("/agent/run", response_model=AgentResponse)
async def run_agent(request: AgentRequest):
    """Non-streaming endpoint (backward compatible)"""
    try:
        # Collect all events from stream
        response_text = ""
        tool_calls = []
        turns = 0

        agent = BedrockAgent(BEDROCK_MODEL_ID)
        async for event in agent.run_stream(request.message, request.max_turns):
            if event["type"] == "text_delta":
                response_text += event["text"]
            elif event["type"] == "done":
                turns = event["turns"]
                tool_calls = event.get("tool_calls", [])
            elif event["type"] == "error":
                return AgentResponse(
                    response=event["error"],
                    turns=event.get("turns", 0),
                    tool_calls=[]
                )

        return AgentResponse(
            response=response_text,
            turns=turns,
            tool_calls=tool_calls
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
```

**Test this step:**
```bash
pytest agent-service/tests/ -v -k "not streaming"
```

**Expected output:** All non-streaming tests should still PASS

---

### Step 9: Write End-to-End Integration Tests

**Goal:** Test complete flow with actual HTTP calls

**File to create:** `agent-service/tests/test_e2e.py`

**Actions:**

9.1. Create end-to-end tests:
```python
import pytest
import json
from fastapi.testclient import TestClient
from unittest.mock import patch
from tests.mock_bedrock import mock_text_only_stream, mock_tool_use_stream, mock_tool_response_stream

@pytest.mark.integration
def test_e2e_non_streaming_backward_compat(mock_mcp_client):
    """Test that non-streaming endpoint still works"""
    from app import app

    with patch('app.mcp_client', mock_mcp_client):
        with patch('app.bedrock') as mock_bedrock:
            mock_bedrock.converse_stream.return_value = mock_text_only_stream()

            client = TestClient(app)
            response = client.post(
                "/agent/run",
                json={"message": "Hello"}
            )

            assert response.status_code == 200
            data = response.json()
            assert "response" in data
            assert "turns" in data
            assert "tool_calls" in data
            assert data["turns"] == 1

@pytest.mark.integration
def test_e2e_streaming_full_flow(mock_mcp_client):
    """Test complete streaming flow from request to completion"""
    from app import app

    mock_mcp_client.execute_tool.return_value = '12'

    with patch('app.mcp_client', mock_mcp_client):
        with patch('app.bedrock') as mock_bedrock:
            mock_bedrock.converse_stream.side_effect = [
                mock_tool_use_stream(),
                mock_tool_response_stream()
            ]

            client = TestClient(app)
            with client.stream("POST", "/agent/stream", json={"message": "sqrt 144"}) as response:
                # Collect all events
                events = []
                full_text = ""

                for line in response.iter_lines():
                    if line.startswith("data: "):
                        event = json.loads(line[6:])
                        events.append(event)

                        if event['type'] == 'text_delta':
                            full_text += event['text']

                # Verify event sequence
                event_types = [e['type'] for e in events]

                # Should have: tool_use_start -> tool_executing -> tool_result -> text_deltas -> done
                assert 'tool_use_start' in event_types
                assert 'tool_executing' in event_types
                assert 'tool_result' in event_types
                assert 'text_delta' in event_types
                assert 'done' in event_types

                # Should have accumulated text
                assert len(full_text) > 0

                # Done should be last
                assert events[-1]['type'] == 'done'
                assert events[-1]['turns'] == 2

@pytest.mark.integration
def test_e2e_both_endpoints_same_model(mock_mcp_client):
    """Test that both endpoints use the same underlying logic"""
    from app import app

    with patch('app.mcp_client', mock_mcp_client):
        with patch('app.bedrock') as mock_bedrock:
            # Test streaming
            mock_bedrock.converse_stream.return_value = mock_text_only_stream()
            client = TestClient(app)

            with client.stream("POST", "/agent/stream", json={"message": "test"}) as response:
                streaming_events = []
                for line in response.iter_lines():
                    if line.startswith("data: "):
                        streaming_events.append(json.loads(line[6:]))

            streaming_text = ''.join([e['text'] for e in streaming_events if e['type'] == 'text_delta'])

            # Test non-streaming
            mock_bedrock.converse_stream.return_value = mock_text_only_stream()
            response = client.post("/agent/run", json={"message": "test"})
            non_streaming_text = response.json()['response']

            # Should produce same text
            assert streaming_text == non_streaming_text
```

**Test this step:**
```bash
pytest agent-service/tests/test_e2e.py -v -m integration
```

**Expected output:** All integration tests should PASS

---

### Step 10: Manual Testing and Client Examples

**Goal:** Test with real curl commands and create client examples

**Actions:**

10.1. Start the service:
```bash
cd agent-service
uvicorn app:app --reload --port 8000
```

10.2. Test streaming endpoint with curl:
```bash
# Test text response
curl -X POST http://localhost:8000/agent/stream \
  -H "Content-Type: application/json" \
  -d '{"message": "Say hello"}' \
  --no-buffer

# Expected: Stream of SSE events
# data: {"type":"text_delta","text":"Hello"}
# data: {"type":"done","turns":1,"tool_calls":[]}
```

10.3. Create Python client example (`agent-service/tests/client_examples/python_client.py`):
```python
import requests
import json

def stream_agent(message):
    """Stream agent responses"""
    response = requests.post(
        'http://localhost:8000/agent/stream',
        json={'message': message},
        stream=True
    )

    for line in response.iter_lines():
        if line:
            line_str = line.decode('utf-8')
            if line_str.startswith('data: '):
                event = json.loads(line_str[6:])

                if event['type'] == 'text_delta':
                    print(event['text'], end='', flush=True)
                elif event['type'] == 'tool_use_start':
                    print(f"\n[Tool: {event['tool']}]", flush=True)
                elif event['type'] == 'tool_result':
                    print(f"[Result: {event['result']}]", flush=True)
                elif event['type'] == 'done':
                    print(f"\n\nCompleted in {event['turns']} turns")
                elif event['type'] == 'error':
                    print(f"\nError: {event['error']}")

if __name__ == '__main__':
    stream_agent("What is the square root of 144?")
```

10.4. Test Python client:
```bash
python agent-service/tests/client_examples/python_client.py
```

**Expected output:** Real-time streaming text and tool execution

---

## Complete Test Suite

**Run all tests:**
```bash
# Unit tests
pytest agent-service/tests/test_bedrock_parser.py -v
pytest agent-service/tests/test_agent_streaming.py -v

# Integration tests
pytest agent-service/tests/test_endpoint_streaming.py -v
pytest agent-service/tests/test_e2e.py -v

# All tests
pytest agent-service/tests/ -v

# With coverage
pytest agent-service/tests/ -v --cov=app --cov-report=html
```

**Expected coverage:**
- BedrockStreamParser: >95%
- BedrockAgent.run_stream: >90%
- FastAPI endpoints: >85%
- Overall: >90%

---

## Implementation Checklist

- [ ] Step 1: Set up test infrastructure (pytest, fixtures, mocks)
- [ ] Step 2: Write Bedrock parser unit tests
- [ ] Step 3: Implement Bedrock stream parser
- [ ] Step 4: Write agent streaming unit tests
- [ ] Step 5: Implement agent run_stream() method
- [ ] Step 6: Write FastAPI endpoint integration tests
- [ ] Step 7: Implement /agent/stream endpoint
- [ ] Step 8: Update /agent/run for backward compatibility
- [ ] Step 9: Write end-to-end integration tests
- [ ] Step 10: Manual testing and client examples
- [ ] All unit tests passing (>95% coverage)
- [ ] All integration tests passing
- [ ] Manual curl test successful
- [ ] Python client example working
- [ ] Documentation updated
- [ ] Backward compatibility verified

## Backward Compatibility

Keep the existing `/agent/run` endpoint for clients that don't need streaming:

```python
@app.post("/agent/run", response_model=AgentResponse)
async def run_agent(request: AgentRequest):
    """Non-streaming endpoint (legacy)"""
    # Collect all events from stream
    response_text = ""
    tool_calls = []
    turns = 0

    async for event in agent.run_stream(request.message, request.max_turns):
        if event["type"] == "text_delta":
            response_text += event["text"]
        elif event["type"] == "done":
            turns = event["turns"]
            tool_calls = event["tool_calls"]

    return AgentResponse(
        response=response_text,
        turns=turns,
        tool_calls=tool_calls
    )
```

## References

- [AWS Bedrock Converse Stream API](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_ConverseStream.html)
- [FastAPI StreamingResponse](https://fastapi.tiangolo.com/advanced/custom-response/#streamingresponse)
- [Server-Sent Events Specification](https://html.spec.whatwg.org/multipage/server-sent-events.html)
- [MDN SSE Guide](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events)
