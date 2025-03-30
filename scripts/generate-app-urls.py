import os
import glob
import json
import boto3

# Retrieve the project ID and AWS region from environment variables.
PROJECT_ID = os.environ.get('PROJECT_ID')
aws_region = os.environ.get('AWS_REGION')

# Initialize the SSM client.
ssm_client = boto3.client('ssm', region_name=aws_region)

def process_caddyfiles(directory):
    result = []
    
    # Get all .Caddyfile files in the specified directory.
    caddyfiles = glob.glob(os.path.join(directory, '*.Caddyfile'))
    
    for file_path in caddyfiles:
        with open(file_path, 'r') as file:
            # Read the first two lines.
            first_line = file.readline().strip()
            second_line = file.readline().strip()
            
            # Process the first line to extract the name.
            name = first_line[2:] if first_line.startswith('# ') else first_line
            
            # Process the second line to extract the port.
            port = second_line[1:5] if second_line.startswith(':') else second_line
            
            # Use the file name (without extension) as an ID.
            id = os.path.splitext(os.path.basename(file_path))[0]
            
            result.append({
                'name': name,
                'port': port,
                'id': id
            })
    
    return result

# Specify the directory containing the Caddy application files.
directory = '/etc/caddy/apps'

# Process the Caddyfiles.
processed_data = process_caddyfiles(directory)

# Convert the data to a JSON string.
json_data = json.dumps(processed_data, indent=2)

# Construct the parameter name in SSM.
parameter_name = f"/{PROJECT_ID}/apps"

# Store the JSON data in AWS Systems Manager Parameter Store.
response = ssm_client.put_parameter(
    Name=parameter_name,
    Value=json_data,
    Type='String',
    Overwrite=True
)

# Optionally print the response.
print(response)
