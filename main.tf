provider "aws" {
  region  = "eu-west-1"
  profile = "da-dev" 
}


data "aws_caller_identity" "current" {}

resource "aws_iam_role" "example" {
  name = "example_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": ["codebuild.amazonaws.com", "codepipeline.amazonaws.com"]
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "example" {
  name = "example_policy"
  role = aws_iam_role.example.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "codestar-connections:UseConnection",
        "codebuild:StartBuild",
        "codebuild:BatchGetBuilds",
        "logs:CreateLogStream",   
        "logs:CreateLogGroup",    
        "logs:PutLogEvents"   
      ],
      "Resource": "*"
    }
  ]
}
EOF
}





resource "aws_s3_bucket" "example" {
  bucket = "my-dennistest-bucket"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "example" {
  bucket = aws_s3_bucket.example.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "example" {
  bucket = aws_s3_bucket.example.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowRootAccess"
        Effect    = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action    = ["s3:GetObject", "s3:PutObject"]
        Resource  = ["${aws_s3_bucket.example.arn}/*"]
      },
      {
        Sid       = "AllowCodePipelineAccess"
        Effect    = "Allow"
        Principal = {
          AWS = aws_iam_role.example.arn
        }
        Action    = ["s3:GetObject", "s3:PutObject"]
        Resource  = ["${aws_s3_bucket.example.arn}/*"]
      },
      {
        Sid       = "AllowCodePipelineListBucket"
        Effect    = "Allow"
        Principal = {
          AWS = aws_iam_role.example.arn
        }
        Action    = ["s3:ListBucket"]
        Resource  = [aws_s3_bucket.example.arn]
      }
    ]
  })
}



resource "aws_codebuild_project" "example" {
  name          = "test-project"
  description   = "test_project"
  build_timeout = "5"
  service_role  = aws_iam_role.example.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:4.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }
}

resource "aws_codepipeline" "example" {
  name     = "test-pipeline"
  role_arn = aws_iam_role.example.arn

  artifact_store {
    location = aws_s3_bucket.example.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]
      

      configuration = {
        ConnectionArn    = "arn:aws:codestar-connections:eu-west-1:492883160621:connection/21176e3e-23e4-45e0-be96-d62f4000fe13"
        FullRepositoryId = "ajitjisc/test_la-monorepo-22"
        BranchName       = "main"
        OutputArtifactFormat = "CODE_ZIP"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.example.name
      }
    }
  }
}
