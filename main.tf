provider "aws" {
}

resource "random_id" "id" {
  byte_length = 8
}

# frontend

resource "aws_s3_bucket" "frontend_bucket" {
	force_destroy = "true"
	website {
		index_document = "index.html"
	}
}

resource "aws_s3_bucket_object" "indexhtml" {
  key    = "index.html"
  bucket = aws_s3_bucket.frontend_bucket.bucket
	content_type = "text/html"
	content = templatefile("index.html", { BACKEND_URL = aws_api_gateway_deployment.deployment.invoke_url })
}

# API

data "archive_file" "lambda_zip" {
	type = "zip"
	output_path = "/tmp/lambda.zip"
  source {
    content  = file("main.js")
    filename = "main.js"
  }
}

resource "aws_lambda_function" "lambda" {
	function_name = "${random_id.id.hex}-function"

  filename = "${data.archive_file.lambda_zip.output_path}"
  source_code_hash = "${data.archive_file.lambda_zip.output_base64sha256}"

  handler = "main.handler"
  runtime = "nodejs10.x"
  role = "${aws_iam_role.lambda_exec.arn}"
	reserved_concurrent_executions = 4
	environment {
		variables = {
			ALLOWED_ORIGINS = join(" ", ["http://${aws_s3_bucket.frontend_bucket.website_endpoint}"])
		}
	}
}

# Boilerplates to wire everything together

# frontend boilerplate

resource "aws_s3_bucket_policy" "default" {
  bucket = aws_s3_bucket.frontend_bucket.id
  policy = data.aws_iam_policy_document.default.json
}

data "aws_iam_policy_document" "default" {
  statement {
    actions = ["s3:GetObject"]

    resources = ["${aws_s3_bucket.frontend_bucket.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
  }
}

# api boilerplate

data "aws_iam_policy_document" "lambda_exec_role_policy" {
	statement {
		sid = "1"
		actions = [
			"logs:CreateLogGroup",
			"logs:CreateLogStream",
			"logs:PutLogEvents"
		]
		resources = [
			"arn:aws:logs:*:*:*"
		]
	}
}

resource "aws_iam_role_policy" "lambda_exec_role" {
	role = "${aws_iam_role.lambda_exec.id}"
	policy = "${data.aws_iam_policy_document.lambda_exec_role_policy.json}"
}

resource "aws_iam_role" "lambda_exec" {
	assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

# api gw

resource "aws_api_gateway_rest_api" "rest_api" {
	name = "cf-signer-${random_id.id.hex}-rest-api"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = "${aws_api_gateway_rest_api.rest_api.id}"
  parent_id   = "${aws_api_gateway_rest_api.rest_api.root_resource_id}"
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = "${aws_api_gateway_rest_api.rest_api.id}"
  resource_id   = "${aws_api_gateway_resource.proxy.id}"
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = "${aws_api_gateway_rest_api.rest_api.id}"
  resource_id = "${aws_api_gateway_method.proxy.resource_id}"
  http_method = "${aws_api_gateway_method.proxy.http_method}"

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.lambda.invoke_arn}"
}

resource "aws_api_gateway_method" "proxy_root" {
  rest_api_id   = "${aws_api_gateway_rest_api.rest_api.id}"
  resource_id   = "${aws_api_gateway_rest_api.rest_api.root_resource_id}"
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_root" {
  rest_api_id = "${aws_api_gateway_rest_api.rest_api.id}"
  resource_id = "${aws_api_gateway_method.proxy_root.resource_id}"
  http_method = "${aws_api_gateway_method.proxy_root.http_method}"

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.lambda.invoke_arn}"
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    "aws_api_gateway_integration.lambda",
    "aws_api_gateway_integration.lambda_root",
  ]

  rest_api_id = "${aws_api_gateway_rest_api.rest_api.id}"
  stage_name  = "test"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.lambda.arn}"
  principal     = "apigateway.amazonaws.com"

  # The /*/* portion grants access from any method on any resource
  # within the API Gateway "REST API".
  source_arn = "${aws_api_gateway_deployment.deployment.execution_arn}/*/*"
}

output "frontend_url" {
  value = "${aws_s3_bucket.frontend_bucket.website_endpoint}"
}

