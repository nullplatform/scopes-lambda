#!/bin/bash
# Mock CONTEXT data for Lambda scope tests

# Standard CONTEXT for testing - public visibility
export MOCK_CONTEXT_PUBLIC='{
  "scope": {
    "id": "scope-123",
    "slug": "my-scope",
    "nrn": "organization=1:account=2:namespace=3:application=4:scope=5",
    "visibility": "public",
    "capabilities": {
      "runtime": "nodejs20.x",
      "handler": "index.handler",
      "memory": 256,
      "timeout": 30,
      "architecture": "arm64",
      "ephemeral_storage": 512
    }
  },
  "deployment": {
    "id": "deploy-456",
    "status": "creating"
  },
  "account": {"id": "2", "slug": "my-account"},
  "namespace": {"id": "3", "slug": "my-namespace"},
  "application": {"id": "4", "slug": "my-app"},
  "asset": {
    "url": "s3://my-bucket/path/to/code.zip"
  },
  "parameters": {
    "results": [
      {"name": "ENV_VAR_1", "value": "value1"},
      {"name": "ENV_VAR_2", "value": "value2"}
    ]
  },
  "providers": {
    "cloud-providers": {
      "credentials": {
        "access_key_id": "AKIAIOSFODNN7EXAMPLE",
        "secret_access_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        "region": "us-east-1"
      },
      "networking": {
        "hosted_public_zone_id": "Z1234567890ABC"
      }
    },
    "assets-repository": {
      "bucket": "my-assets-bucket"
    }
  }
}'

# Standard CONTEXT for testing - private visibility (ALB)
export MOCK_CONTEXT_PRIVATE='{
  "scope": {
    "id": "scope-789",
    "slug": "my-private-scope",
    "nrn": "organization=1:account=2:namespace=3:application=4:scope=6",
    "visibility": "private",
    "capabilities": {
      "runtime": "python3.12",
      "handler": "lambda_function.handler",
      "memory": 512,
      "timeout": 60,
      "architecture": "x86_64",
      "ephemeral_storage": 1024
    }
  },
  "deployment": {
    "id": "deploy-789",
    "status": "creating"
  },
  "account": {"id": "2", "slug": "my-account"},
  "namespace": {"id": "3", "slug": "my-namespace"},
  "application": {"id": "4", "slug": "my-app"},
  "asset": {
    "url": "s3://my-bucket/private/code.zip"
  },
  "parameters": {
    "results": []
  },
  "providers": {
    "cloud-providers": {
      "credentials": {
        "access_key_id": "AKIAIOSFODNN7EXAMPLE",
        "secret_access_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        "region": "us-east-1"
      },
      "networking": {
        "hosted_zone_id": "Z0987654321XYZ",
        "alb_listener_arn": "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/my-alb/50dc6c495c0c9188/f2f7dc8efc522ab2"
      }
    },
    "assets-repository": {
      "bucket": "my-assets-bucket"
    }
  }
}'

# CONTEXT with VPC configuration
export MOCK_CONTEXT_VPC='{
  "scope": {
    "id": "scope-vpc",
    "slug": "my-vpc-scope",
    "nrn": "organization=1:account=2:namespace=3:application=4:scope=7",
    "visibility": "public",
    "capabilities": {
      "runtime": "nodejs20.x",
      "handler": "index.handler",
      "memory": 256,
      "timeout": 30,
      "architecture": "arm64",
      "vpc_enabled": true
    }
  },
  "deployment": {
    "id": "deploy-vpc",
    "status": "creating"
  },
  "account": {"id": "2", "slug": "my-account"},
  "namespace": {"id": "3", "slug": "my-namespace"},
  "application": {"id": "4", "slug": "my-app"},
  "asset": {
    "url": "s3://my-bucket/vpc/code.zip"
  },
  "parameters": {
    "results": []
  },
  "providers": {
    "cloud-providers": {
      "credentials": {
        "access_key_id": "AKIAIOSFODNN7EXAMPLE",
        "secret_access_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        "region": "us-east-1"
      },
      "networking": {
        "hosted_public_zone_id": "Z1234567890ABC",
        "vpc_id": "vpc-12345678",
        "subnet_ids": ["subnet-11111111", "subnet-22222222"],
        "security_group_ids": ["sg-12345678"]
      }
    },
    "assets-repository": {
      "bucket": "my-assets-bucket"
    }
  }
}'

# CONTEXT with provisioned concurrency
export MOCK_CONTEXT_PROVISIONED='{
  "scope": {
    "id": "scope-prov",
    "slug": "my-provisioned-scope",
    "nrn": "organization=1:account=2:namespace=3:application=4:scope=8",
    "visibility": "public",
    "capabilities": {
      "runtime": "nodejs20.x",
      "handler": "index.handler",
      "memory": 512,
      "timeout": 30,
      "architecture": "arm64",
      "provisioned_concurrency": {
        "type": "provisioned",
        "value": 5
      },
      "reserved_concurrency": {
        "type": "reserved",
        "value": 10
      }
    }
  },
  "deployment": {
    "id": "deploy-prov",
    "status": "creating"
  },
  "account": {"id": "2", "slug": "my-account"},
  "namespace": {"id": "3", "slug": "my-namespace"},
  "application": {"id": "4", "slug": "my-app"},
  "asset": {
    "url": "s3://my-bucket/prov/code.zip"
  },
  "parameters": {
    "results": []
  },
  "providers": {
    "cloud-providers": {
      "credentials": {
        "access_key_id": "AKIAIOSFODNN7EXAMPLE",
        "secret_access_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        "region": "us-east-1"
      },
      "networking": {
        "hosted_public_zone_id": "Z1234567890ABC"
      }
    },
    "assets-repository": {
      "bucket": "my-assets-bucket"
    }
  }
}'

# CONTEXT with Lambda layers
export MOCK_CONTEXT_LAYERS='{
  "scope": {
    "id": "scope-layers",
    "slug": "my-layered-scope",
    "nrn": "organization=1:account=2:namespace=3:application=4:scope=9",
    "visibility": "public",
    "capabilities": {
      "runtime": "nodejs20.x",
      "handler": "index.handler",
      "memory": 256,
      "timeout": 30,
      "architecture": "arm64",
      "layers": [
        "arn:aws:lambda:us-east-1:123456789012:layer:my-custom-layer:1",
        "arn:aws:lambda:us-east-1:123456789012:layer:another-layer:5"
      ]
    }
  },
  "deployment": {
    "id": "deploy-layers",
    "status": "creating"
  },
  "account": {"id": "2", "slug": "my-account"},
  "namespace": {"id": "3", "slug": "my-namespace"},
  "application": {"id": "4", "slug": "my-app"},
  "asset": {
    "url": "s3://my-bucket/layers/code.zip"
  },
  "parameters": {
    "results": []
  },
  "providers": {
    "cloud-providers": {
      "credentials": {
        "access_key_id": "AKIAIOSFODNN7EXAMPLE",
        "secret_access_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        "region": "us-east-1"
      },
      "networking": {
        "hosted_public_zone_id": "Z1234567890ABC"
      }
    },
    "assets-repository": {
      "bucket": "my-assets-bucket"
    }
  }
}'

# CONTEXT with docker-image asset (ECR/container image)
export MOCK_CONTEXT_DOCKER_IMAGE='{
  "scope": {
    "id": "scope-docker",
    "slug": "my-docker-scope",
    "nrn": "organization=1:account=2:namespace=3:application=4:scope=11",
    "visibility": "public",
    "capabilities": {
      "memory": 512,
      "timeout": 30,
      "architecture": "x86_64",
      "ephemeral_storage": 512
    }
  },
  "deployment": {
    "id": "deploy-docker",
    "status": "creating"
  },
  "account": {"id": "2", "slug": "my-account"},
  "namespace": {"id": "3", "slug": "my-namespace"},
  "application": {"id": "4", "slug": "my-app"},
  "asset": {
    "url": "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-app:v1.0.0",
    "type": "docker-image"
  },
  "parameters": {
    "results": [
      {"name": "ENV_VAR_1", "value": "value1"},
      {"name": "ENV_VAR_2", "value": "value2"}
    ]
  },
  "providers": {
    "cloud-providers": {
      "credentials": {
        "access_key_id": "AKIAIOSFODNN7EXAMPLE",
        "secret_access_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        "region": "us-east-1"
      },
      "networking": {
        "hosted_public_zone_id": "Z1234567890ABC"
      }
    },
    "assets-repository": {
      "bucket": "my-assets-bucket"
    }
  }
}'

# CONTEXT for Secrets Manager parameter strategy tests
export MOCK_CONTEXT_SECRETSMANAGER='{
  "scope": {
    "id": "scope-sm",
    "slug": "my-sm-scope",
    "nrn": "organization=1:account=2:namespace=3:application=4:scope=12",
    "visibility": "public",
    "capabilities": {
      "runtime": "nodejs20.x",
      "handler": "index.handler",
      "memory": 256,
      "timeout": 30,
      "architecture": "arm64",
      "ephemeral_storage": 512
    }
  },
  "deployment": {
    "id": "deploy-sm",
    "status": "creating"
  },
  "account": {"id": "2", "slug": "my-account"},
  "namespace": {"id": "3", "slug": "my-namespace"},
  "application": {"id": "4", "slug": "my-app"},
  "asset": {
    "url": "s3://my-bucket/path/to/code.zip"
  },
  "parameters": {
    "results": [
      {"name": "DB_HOST", "value": "db.example.com"},
      {"name": "DB_PASSWORD", "value": "secret123", "secret": true},
      {"name": "API_KEY", "value": "key-abc-123", "secret": true}
    ]
  },
  "providers": {
    "cloud-providers": {
      "credentials": {
        "access_key_id": "AKIAIOSFODNN7EXAMPLE",
        "secret_access_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        "region": "us-east-1"
      },
      "networking": {
        "hosted_public_zone_id": "Z1234567890ABC"
      }
    },
    "assets-repository": {
      "bucket": "my-assets-bucket"
    }
  }
}'

# Minimal CONTEXT for simple tests
export MOCK_CONTEXT_MINIMAL='{
  "scope": {
    "id": "scope-min",
    "slug": "minimal-scope",
    "nrn": "organization=1:account=2:namespace=3:application=4:scope=10",
    "visibility": "public",
    "capabilities": {}
  },
  "deployment": {
    "id": "deploy-min",
    "status": "creating"
  },
  "account": {"id": "2", "slug": "my-account"},
  "namespace": {"id": "3", "slug": "my-namespace"},
  "application": {"id": "4", "slug": "my-app"},
  "asset": {
    "url": "s3://my-bucket/min/code.zip"
  },
  "parameters": {
    "results": []
  },
  "providers": {
    "cloud-providers": {
      "credentials": {
        "access_key_id": "AKIAIOSFODNN7EXAMPLE",
        "secret_access_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        "region": "us-east-1"
      },
      "networking": {
        "hosted_public_zone_id": "Z1234567890ABC"
      }
    },
    "assets-repository": {
      "bucket": "my-assets-bucket"
    }
  }
}'

# Helper function to set CONTEXT for tests
set_context() {
  local context_type="${1:-public}"

  case "$context_type" in
    public)
      export CONTEXT="$MOCK_CONTEXT_PUBLIC"
      ;;
    private)
      export CONTEXT="$MOCK_CONTEXT_PRIVATE"
      ;;
    vpc)
      export CONTEXT="$MOCK_CONTEXT_VPC"
      ;;
    provisioned)
      export CONTEXT="$MOCK_CONTEXT_PROVISIONED"
      ;;
    layers)
      export CONTEXT="$MOCK_CONTEXT_LAYERS"
      ;;
    minimal)
      export CONTEXT="$MOCK_CONTEXT_MINIMAL"
      ;;
    docker_image)
      export CONTEXT="$MOCK_CONTEXT_DOCKER_IMAGE"
      ;;
    secretsmanager)
      export CONTEXT="$MOCK_CONTEXT_SECRETSMANAGER"
      ;;
    *)
      echo "Unknown context type: $context_type" >&2
      return 1
      ;;
  esac
}

# Export functions
export -f set_context
