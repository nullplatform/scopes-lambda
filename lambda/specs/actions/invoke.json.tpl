{
  "name": "Invoke",
  "slug": "invoke",
  "type": "custom",
  "retryable": true,
  "service_specification_id": "{{ env.Getenv "SERVICE_SPECIFICATION_ID" }}",
  "icon": "material-symbols:pin-invoke-rounded",
  "annotations": {
    "show_on": ["performance"],
    "runs_over": "scope"
  },
  "enabled_when": "",
  "parameters": {
    "schema": {
      "type": "object",
      "required": [
        "scope_id"
      ],
      "properties": {
        "scope_id": {
          "type": "number",
          "readOnly": true,
          "visibleOn": []
        },
        "payload": {
          "type": "string",
          "description": "JSON payload to send to the Lambda function (optional)",
          "default": "{}"
        }
      }
    },
    "values": {}
  },
  "results": {
    "schema": {
      "type": "object",
      "required": [],
      "properties": {}
    },
    "values": {}
  }
}
