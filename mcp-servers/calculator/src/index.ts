import express, { Request, Response } from 'express';
import cors from 'cors';

const app = express();
const PORT = process.env.PORT || 3002;

app.use(cors());
app.use(express.json());

// Tool definitions following MCP schema
const TOOLS = [
  {
    name: 'add',
    description: 'Add two numbers together',
    inputSchema: {
      type: 'object',
      properties: {
        a: {
          type: 'number',
          description: 'First number'
        },
        b: {
          type: 'number',
          description: 'Second number'
        }
      },
      required: ['a', 'b']
    }
  },
  {
    name: 'subtract',
    description: 'Subtract second number from first number',
    inputSchema: {
      type: 'object',
      properties: {
        a: {
          type: 'number',
          description: 'First number'
        },
        b: {
          type: 'number',
          description: 'Second number'
        }
      },
      required: ['a', 'b']
    }
  },
  {
    name: 'multiply',
    description: 'Multiply two numbers',
    inputSchema: {
      type: 'object',
      properties: {
        a: {
          type: 'number',
          description: 'First number'
        },
        b: {
          type: 'number',
          description: 'Second number'
        }
      },
      required: ['a', 'b']
    }
  },
  {
    name: 'divide',
    description: 'Divide first number by second number',
    inputSchema: {
      type: 'object',
      properties: {
        a: {
          type: 'number',
          description: 'Numerator'
        },
        b: {
          type: 'number',
          description: 'Denominator'
        }
      },
      required: ['a', 'b']
    }
  },
  {
    name: 'power',
    description: 'Raise first number to the power of second number',
    inputSchema: {
      type: 'object',
      properties: {
        base: {
          type: 'number',
          description: 'Base number'
        },
        exponent: {
          type: 'number',
          description: 'Exponent'
        }
      },
      required: ['base', 'exponent']
    }
  },
  {
    name: 'sqrt',
    description: 'Calculate square root of a number',
    inputSchema: {
      type: 'object',
      properties: {
        number: {
          type: 'number',
          description: 'Number to calculate square root of'
        }
      },
      required: ['number']
    }
  }
];

// Health check endpoint
app.get('/', (req: Request, res: Response) => {
  res.json({
    service: 'MCP Calculator Server',
    status: 'running'
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
      case 'add':
        result = {
          operation: 'addition',
          inputs: [args.a, args.b],
          result: args.a + args.b
        };
        break;

      case 'subtract':
        result = {
          operation: 'subtraction',
          inputs: [args.a, args.b],
          result: args.a - args.b
        };
        break;

      case 'multiply':
        result = {
          operation: 'multiplication',
          inputs: [args.a, args.b],
          result: args.a * args.b
        };
        break;

      case 'divide':
        if (args.b === 0) {
          return res.status(400).json({
            error: 'Division by zero is not allowed'
          });
        }
        result = {
          operation: 'division',
          inputs: [args.a, args.b],
          result: args.a / args.b
        };
        break;

      case 'power':
        result = {
          operation: 'exponentiation',
          base: args.base,
          exponent: args.exponent,
          result: Math.pow(args.base, args.exponent)
        };
        break;

      case 'sqrt':
        if (args.number < 0) {
          return res.status(400).json({
            error: 'Cannot calculate square root of negative number'
          });
        }
        result = {
          operation: 'square root',
          input: args.number,
          result: Math.sqrt(args.number)
        };
        break;

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
  console.log(`MCP Calculator Server running on port ${PORT}`);
});
