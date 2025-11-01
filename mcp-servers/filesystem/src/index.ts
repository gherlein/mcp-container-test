import express, { Request, Response } from 'express';
import cors from 'cors';
import * as fs from 'fs/promises';
import * as path from 'path';

const app = express();
const PORT = process.env.PORT || 3001;
const WORKSPACE_ROOT = process.env.WORKSPACE_ROOT || '/workspace';

app.use(cors());
app.use(express.json());

// Tool definitions following MCP schema
const TOOLS = [
  {
    name: 'read_file',
    description: 'Read the contents of a file',
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'Path to the file to read (relative to workspace)'
        }
      },
      required: ['path']
    }
  },
  {
    name: 'write_file',
    description: 'Write content to a file',
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'Path to the file to write (relative to workspace)'
        },
        content: {
          type: 'string',
          description: 'Content to write to the file'
        }
      },
      required: ['path', 'content']
    }
  },
  {
    name: 'list_directory',
    description: 'List contents of a directory',
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'Path to the directory to list (relative to workspace, defaults to root)'
        }
      },
      required: []
    }
  },
  {
    name: 'create_directory',
    description: 'Create a new directory',
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'Path to the directory to create (relative to workspace)'
        }
      },
      required: ['path']
    }
  }
];

// Utility to resolve and validate paths
function resolvePath(relativePath: string): string {
  const resolved = path.resolve(WORKSPACE_ROOT, relativePath || '.');
  // Ensure path is within workspace
  if (!resolved.startsWith(WORKSPACE_ROOT)) {
    throw new Error('Path is outside workspace');
  }
  return resolved;
}

// Health check endpoint
app.get('/', (req: Request, res: Response) => {
  res.json({
    service: 'MCP Filesystem Server',
    status: 'running',
    workspace: WORKSPACE_ROOT
  });
});

// List available tools
app.get('/tools', (req: Request, res: Response) => {
  res.json({ tools: TOOLS });
});

// Execute tool
app.post('/execute', async (req: Request, res: Response) => {
  const { tool, arguments: args } = req.body;

  try {
    let result: any;

    switch (tool) {
      case 'read_file': {
        const filePath = resolvePath(args.path);
        const content = await fs.readFile(filePath, 'utf-8');
        result = {
          content,
          path: args.path,
          size: content.length
        };
        break;
      }

      case 'write_file': {
        const filePath = resolvePath(args.path);
        // Ensure directory exists
        await fs.mkdir(path.dirname(filePath), { recursive: true });
        await fs.writeFile(filePath, args.content, 'utf-8');
        result = {
          success: true,
          path: args.path,
          bytes_written: args.content.length
        };
        break;
      }

      case 'list_directory': {
        const dirPath = resolvePath(args.path || '.');
        const entries = await fs.readdir(dirPath, { withFileTypes: true });
        const items = await Promise.all(
          entries.map(async (entry) => {
            const itemPath = path.join(dirPath, entry.name);
            const stats = await fs.stat(itemPath);
            return {
              name: entry.name,
              type: entry.isDirectory() ? 'directory' : 'file',
              size: stats.size,
              modified: stats.mtime.toISOString()
            };
          })
        );
        result = {
          path: args.path || '.',
          items,
          count: items.length
        };
        break;
      }

      case 'create_directory': {
        const dirPath = resolvePath(args.path);
        await fs.mkdir(dirPath, { recursive: true });
        result = {
          success: true,
          path: args.path
        };
        break;
      }

      default:
        return res.status(400).json({
          error: `Unknown tool: ${tool}`
        });
    }

    res.json({ result });
  } catch (error: any) {
    console.error(`Error executing ${tool}:`, error);
    res.status(500).json({
      error: error.message || 'Tool execution failed'
    });
  }
});

app.listen(PORT, () => {
  console.log(`MCP Filesystem Server running on port ${PORT}`);
  console.log(`Workspace root: ${WORKSPACE_ROOT}`);
});
