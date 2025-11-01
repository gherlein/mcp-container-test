import os
import json
import asyncio
from typing import List, Dict, Any, Optional
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import boto3
from botocore.exceptions import ClientError
import httpx

app = FastAPI(title="Bedrock Agent Service")

# Configuration
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
BEDROCK_MODEL_ID = os.getenv("BEDROCK_MODEL_ID", "anthropic.claude-3-5-sonnet-20241022-v2:0")
MCP_FILESYSTEM_URL = os.getenv("MCP_FILESYSTEM_URL", "http://mcp-filesystem:3001")
MCP_CALCULATOR_URL = os.getenv("MCP_CALCULATOR_URL", "http://mcp-calculator:3002")

# Initialize Bedrock client
bedrock = boto3.client('bedrock-runtime', region_name=AWS_REGION)

# MCP Server registry
MCP_SERVERS = {
    "filesystem": MCP_FILESYSTEM_URL,
    "calculator": MCP_CALCULATOR_URL
}


class Message(BaseModel):
    role: str
    content: str


class AgentRequest(BaseModel):
    message: str
    max_turns: Optional[int] = 10


class AgentResponse(BaseModel):
    response: str
    turns: int
    tool_calls: List[Dict[str, Any]]


class MCPClient:
    """Client for interacting with MCP servers via HTTP"""

    def __init__(self):
        self.tools_cache = None
        self.tool_to_server = {}

    async def fetch_all_tools(self) -> List[Dict[str, Any]]:
        """Fetch tools from all MCP servers and convert to Bedrock format"""
        if self.tools_cache is not None:
            return self.tools_cache

        all_tools = []

        async with httpx.AsyncClient() as client:
            for server_name, server_url in MCP_SERVERS.items():
                try:
                    response = await client.get(f"{server_url}/tools")
                    if response.status_code == 200:
                        tools_data = response.json()
                        for tool in tools_data.get("tools", []):
                            # Convert MCP tool schema to Bedrock format
                            bedrock_tool = {
                                "toolSpec": {
                                    "name": tool["name"],
                                    "description": tool.get("description", ""),
                                    "inputSchema": {
                                        "json": tool.get("inputSchema", {
                                            "type": "object",
                                            "properties": {},
                                            "required": []
                                        })
                                    }
                                }
                            }
                            all_tools.append(bedrock_tool)
                            # Map tool name to server
                            self.tool_to_server[tool["name"]] = server_url
                except Exception as e:
                    print(f"Error fetching tools from {server_name}: {e}")

        self.tools_cache = all_tools
        return all_tools

    async def execute_tool(self, tool_name: str, tool_input: Dict[str, Any]) -> str:
        """Execute a tool call on the appropriate MCP server"""
        server_url = self.tool_to_server.get(tool_name)
        if not server_url:
            return json.dumps({"error": f"Tool {tool_name} not found"})

        try:
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    f"{server_url}/execute",
                    json={
                        "tool": tool_name,
                        "arguments": tool_input
                    },
                    timeout=30.0
                )

                if response.status_code == 200:
                    result = response.json()
                    return json.dumps(result.get("result", result))
                else:
                    return json.dumps({
                        "error": f"Tool execution failed: {response.status_code}",
                        "details": response.text
                    })
        except Exception as e:
            return json.dumps({"error": f"Tool execution error: {str(e)}"})


mcp_client = MCPClient()


class BedrockAgent:
    """Agent that uses Bedrock with MCP tools"""

    def __init__(self, model_id: str):
        self.model_id = model_id

    async def run(self, user_message: str, max_turns: int = 10) -> AgentResponse:
        """Run the agent loop"""
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
                # Call Bedrock with tool configuration
                response = bedrock.converse(
                    modelId=self.model_id,
                    messages=messages,
                    toolConfig={
                        "tools": tools,
                        "toolChoice": {"auto": {}}
                    } if tools else None
                )

                stop_reason = response.get("stopReason")
                output_message = response["output"]["message"]

                # Add assistant message to conversation
                messages.append(output_message)

                if stop_reason == "end_turn":
                    # Extract text response
                    text_content = ""
                    for content in output_message.get("content", []):
                        if "text" in content:
                            text_content += content["text"]

                    return AgentResponse(
                        response=text_content,
                        turns=turns,
                        tool_calls=tool_calls_log
                    )

                elif stop_reason == "tool_use":
                    # Execute tools
                    tool_results = []

                    for content in output_message.get("content", []):
                        if "toolUse" in content:
                            tool_use = content["toolUse"]
                            tool_name = tool_use["name"]
                            tool_input = tool_use["input"]
                            tool_use_id = tool_use["toolUseId"]

                            # Log tool call
                            tool_calls_log.append({
                                "tool": tool_name,
                                "input": tool_input,
                                "tool_use_id": tool_use_id
                            })

                            # Execute tool via MCP
                            result = await mcp_client.execute_tool(tool_name, tool_input)

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

                elif stop_reason == "max_tokens":
                    return AgentResponse(
                        response="Response truncated due to max tokens",
                        turns=turns,
                        tool_calls=tool_calls_log
                    )

                else:
                    return AgentResponse(
                        response=f"Unexpected stop reason: {stop_reason}",
                        turns=turns,
                        tool_calls=tool_calls_log
                    )

            except ClientError as e:
                error_message = f"Bedrock API error: {e.response['Error']['Message']}"
                return AgentResponse(
                    response=error_message,
                    turns=turns,
                    tool_calls=tool_calls_log
                )

            except Exception as e:
                error_message = f"Agent error: {str(e)}"
                return AgentResponse(
                    response=error_message,
                    turns=turns,
                    tool_calls=tool_calls_log
                )

        return AgentResponse(
            response="Max turns reached",
            turns=turns,
            tool_calls=tool_calls_log
        )


@app.get("/")
async def root():
    return {
        "service": "Bedrock Agent Service",
        "status": "running",
        "model": BEDROCK_MODEL_ID
    }


@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "healthy"}


@app.get("/tools")
async def list_tools():
    """List all available tools from MCP servers"""
    try:
        tools = await mcp_client.fetch_all_tools()
        return {
            "tools": tools,
            "count": len(tools)
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/agent/run", response_model=AgentResponse)
async def run_agent(request: AgentRequest):
    """Run the agent with a user message"""
    try:
        agent = BedrockAgent(BEDROCK_MODEL_ID)
        result = await agent.run(request.message, request.max_turns)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
