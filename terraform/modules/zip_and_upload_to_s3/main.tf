data "archive_file" "zip_file" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "../../../${path.module}/${var.output_filename}"
  excludes    = []
  
  depends_on = [null_resource.force_zip_update]
}

resource "null_resource" "force_zip_update" {
  triggers = {
    always_run = timestamp()
  }
}

resource "aws_s3_object" "zip_upload" {
  bucket       = var.bucket_name
  key          = "code/${var.output_filename}"
  source       = data.archive_file.zip_file.output_path
  content_type = "application/zip"
  etag         = filemd5(data.archive_file.zip_file.output_path)
}