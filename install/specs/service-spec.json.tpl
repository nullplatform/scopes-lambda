{
  "assignable_to": "any",
  "attributes": {
    "schema": {
      "type": "object",
      "required": [
        "deployment_type",
        "handler",
        "memory",
        "timeout",
        "architecture",
        "http_enabled",
        "visibility",
        "continuous_delivery",
        "ephemeral_storage",
        "layers",
        "vpc_enabled",
        "reserved_concurrency",
        "provisioned_concurrency"
      ],
      "uiSchema": {
        "type": "VerticalLayout",
        "elements": [
          {
            "type": "Control",
            "label": "Deployment Type",
            "scope": "#/properties/deployment_type",
            "options": {
              "format": "radio"
            }
          },
          {
            "rule": {
              "effect": "SHOW",
              "condition": {
                "scope": "#/properties/deployment_type",
                "schema": {
                  "const": "zip"
                }
              }
            },
            "type": "Control",
            "label": "Runtime",
            "scope": "#/properties/runtime"
          },
          {
            "type": "Control",
            "label": "Handler",
            "scope": "#/properties/handler"
          },
          {
            "type": "Control",
            "label": "Memory",
            "scope": "#/properties/memory"
          },
          {
            "type": "Control",
            "label": "Expose via HTTP",
            "scope": "#/properties/http_enabled"
          },
          {
            "rule": {
              "effect": "SHOW",
              "condition": {
                "scope": "#/properties/http_enabled",
                "schema": {
                  "const": true
                }
              }
            },
            "type": "Control",
            "label": "Visibility",
            "scope": "#/properties/visibility",
            "options": {
              "format": "radio"
            }
          },
          {
            "type": "Categorization",
            "options": {
              "collapsable": {
                "label": "ADVANCED",
                "collapsed": true
              }
            },
            "elements": [
              {
                "type": "Category",
                "label": "Execution",
                "elements": [
                  {
                    "type": "Control",
                    "scope": "#/properties/timeout"
                  },
                  {
                    "type": "Control",
                    "scope": "#/properties/ephemeral_storage"
                  },
                  {
                    "type": "Control",
                    "scope": "#/properties/architecture"
                  }
                ]
              },
              {
                "type": "Category",
                "label": "Concurrency",
                "elements": [
                  {
                    "type": "Control",
                    "scope": "#/properties/reserved_concurrency/properties/type"
                  },
                  {
                    "rule": {
                      "effect": "SHOW",
                      "condition": {
                        "scope": "#/properties/reserved_concurrency/properties/type",
                        "schema": {
                          "enum": ["reserved"]
                        }
                      }
                    },
                    "type": "Control",
                    "scope": "#/properties/reserved_concurrency/properties/value"
                  },
                  {
                    "type": "Control",
                    "scope": "#/properties/provisioned_concurrency/properties/type"
                  },
                  {
                    "rule": {
                      "effect": "SHOW",
                      "condition": {
                        "scope": "#/properties/provisioned_concurrency/properties/type",
                        "schema": {
                          "enum": ["provisioned"]
                        }
                      }
                    },
                    "type": "Control",
                    "scope": "#/properties/provisioned_concurrency/properties/value"
                  },
                  {
                    "rule": {
                      "effect": "SHOW",
                      "condition": {
                        "scope": "#/properties/provisioned_concurrency/properties/type",
                        "schema": {
                          "enum": ["provisioned"]
                        }
                      }
                    },
                    "type": "Control",
                    "scope": "#/properties/provisioned_concurrency/properties/warmup_alias"
                  }
                ]
              },
              {
                "type": "Category",
                "label": "Networking",
                "elements": [
                  {
                    "type": "Control",
                    "scope": "#/properties/vpc_enabled"
                  }
                ]
              },
              {
                "type": "Category",
                "label": "Layers",
                "elements": [
                  {
                    "type": "Control",
                    "scope": "#/properties/layers"
                  }
                ]
              },
              {
                "type": "Category",
                "label": "Continuous Deployment",
                "elements": [
                  {
                    "type": "Control",
                    "scope": "#/properties/continuous_delivery/properties/enabled"
                  },
                  {
                    "rule": {
                      "effect": "SHOW",
                      "condition": {
                        "scope": "#/properties/continuous_delivery/properties/enabled",
                        "schema": {
                          "const": true
                        }
                      }
                    },
                    "type": "Control",
                    "scope": "#/properties/continuous_delivery/properties/branches"
                  }
                ]
              }
            ]
          }
        ]
      },
      "properties": {
        "deployment_type": {
          "type": "string",
          "title": "Deployment Type",
          "description": "Choose how your Lambda function is packaged and deployed. Cannot be changed after scope creation.",
          "default": "docker-image",
          "editableOn": ["create"],
          "oneOf": [
            { "const": "docker-image", "title": "Docker Image (ECR)" },
            { "const": "zip", "title": "ZIP Package (S3)" }
          ]
        },
        "asset_type": {
          "type": "string",
          "export": false,
          "default": "docker-image"
        },
        "runtime": {
          "type": "string",
          "title": "Runtime",
          "description": "Lambda runtime environment for your ZIP deployment",
          "default": "nodejs20.x",
          "oneOf": [
            { "const": "nodejs20.x", "title": "Node.js 20.x" },
            { "const": "nodejs18.x", "title": "Node.js 18.x" },
            { "const": "python3.13", "title": "Python 3.13" },
            { "const": "python3.12", "title": "Python 3.12" },
            { "const": "python3.11", "title": "Python 3.11" },
            { "const": "python3.10", "title": "Python 3.10" },
            { "const": "java21", "title": "Java 21" },
            { "const": "java17", "title": "Java 17" },
            { "const": "java11", "title": "Java 11" },
            { "const": "dotnet8", "title": ".NET 8" },
            { "const": "ruby3.3", "title": "Ruby 3.3" },
            { "const": "provided.al2023", "title": "Custom Runtime (Amazon Linux 2023)" }
          ]
        },
        "handler": {
          "type": "string",
          "title": "Handler",
          "default": "index.handler",
          "description": "Function entry point (e.g., index.handler for Node.js, app.lambda_handler for Python)"
        },
        "memory": {
          "type": "integer",
          "title": "Memory (MB)",
          "description": "Amount of memory allocated to your function in MB (128-10240). CPU scales proportionally.",
          "default": 256,
          "minimum": 128,
          "maximum": 10240
        },
        "timeout": {
          "type": "integer",
          "title": "Timeout (seconds)",
          "description": "Maximum execution time before the function is terminated",
          "default": 30,
          "minimum": 3,
          "maximum": 900
        },
        "ephemeral_storage": {
          "type": "integer",
          "title": "Ephemeral Storage (MB)",
          "description": "Temporary disk space available in /tmp",
          "default": 512,
          "oneOf": [
            { "const": 512, "title": "512 MB" },
            { "const": 1024, "title": "1 GB" },
            { "const": 2048, "title": "2 GB" },
            { "const": 3072, "title": "3 GB" },
            { "const": 4096, "title": "4 GB" },
            { "const": 5120, "title": "5 GB" },
            { "const": 6144, "title": "6 GB" },
            { "const": 7168, "title": "7 GB" },
            { "const": 8192, "title": "8 GB" },
            { "const": 9216, "title": "9 GB" },
            { "const": 10240, "title": "10 GB" }
          ]
        },
        "architecture": {
          "type": "string",
          "title": "Architecture",
          "description": "CPU architecture (ARM is more cost-effective, x86 has broader compatibility)",
          "default": "arm64",
          "oneOf": [
            { "const": "arm64", "title": "ARM64 (Graviton2)" },
            { "const": "x86_64", "title": "x86_64" }
          ]
        },
        "http_enabled": {
          "type": "boolean",
          "title": "Expose via HTTP",
          "description": "When enabled, your function is accessible via an HTTP endpoint. Disable this for functions triggered exclusively by internal events (queues, streams, schedules, etc.).",
          "default": true
        },
        "visibility": {
          "type": "string",
          "title": "Visibility",
          "description": "How your function is accessed",
          "default": "public",
          "oneOf": [
            { "const": "public", "title": "Public" },
            { "const": "private", "title": "Private" }
          ]
        },
        "reserved_concurrency": {
          "type": "object",
          "title": "Reserved Concurrency",
          "properties": {
            "type": {
              "type": "string",
              "title": "Reserved Concurrency",
              "description": "Sets a hard limit on how many concurrent executions your function can have, throttling any requests beyond that number.",
              "default": "unreserved",
              "oneOf": [
                { "const": "unreserved", "title": "Unreserved (shared pool)" },
                { "const": "reserved", "title": "Reserved (dedicated capacity)" }
              ]
            },
            "value": {
              "type": "integer",
              "title": "Reserved Instances",
              "description": "Number of concurrent executions to reserve",
              "default": 10,
              "minimum": 1,
              "maximum": 1000
            }
          }
        },
        "provisioned_concurrency": {
          "type": "object",
          "title": "Provisioned Concurrency",
          "properties": {
            "type": {
              "type": "string",
              "title": "Provisioned Concurrency",
              "description": "Pre-warms a fixed number of execution environments so they're always ready to respond instantly, eliminating cold starts — but you're billed for those instances continuously, even when idle.",
              "default": "unprovisioned",
              "oneOf": [
                { "const": "unprovisioned", "title": "Disabled (cold starts allowed)" },
                { "const": "provisioned", "title": "Enabled (pre-warmed instances)" }
              ]
            },
            "value": {
              "type": "integer",
              "title": "Provisioned Instances",
              "description": "Number of pre-initialized execution environments",
              "default": 5,
              "minimum": 1,
              "maximum": 500
            },
            "warmup_alias": {
              "type": "string",
              "title": "Warmup Alias",
              "description": "Separate alias for pre-warming new versions before traffic shift (leave empty to disable)",
              "default": ""
            }
          }
        },
        "vpc_enabled": {
          "type": "boolean",
          "title": "VPC Integration",
          "description": "Run Lambda inside your VPC for access to private resources",
          "default": false
        },
        "layers": {
          "type": "array",
          "title": "Custom Layers",
          "description": "Additional Lambda layers (libraries, custom runtimes). Enter full ARN for each layer.",
          "items": {
            "type": "string"
          },
          "default": []
        },
        "continuous_delivery": {
          "type": "object",
          "title": "Continuous Delivery",
          "required": ["enabled", "branches"],
          "properties": {
            "enabled": {
              "type": "boolean",
              "title": "Enable Continuous Delivery",
              "default": false,
              "description": "Automatically deploy new versions from specified branches"
            },
            "branches": {
              "type": "array",
              "items": {
                "type": "string"
              },
              "title": "Branches",
              "default": ["main"],
              "description": "Git branches to monitor for automatic deployment"
            }
          },
          "description": "Configure automatic deployment from Git branches"
        }
      }
    }
  },
  "name": "AWS Lambda",
  "selectors": {
    "category": "Scope",
    "imported": false,
    "provider": "Agent",
    "sub_category": "Lambda"
  },
  "type": "scope",
  "use_default_actions": false,
  "visible_to": [
    "{{ env.Getenv "NRN" }}"
  ]
}
