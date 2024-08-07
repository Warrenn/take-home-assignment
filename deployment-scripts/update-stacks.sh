#!/bin/bash

set -e

# Get the current directory 
export current_dir=$(pwd)
echo "Current directory: $current_dir"

# Get the absolute path of the script
export script_path=$(cd $(dirname $0); pwd -P)
echo "Script path: $script_path"

# Get the absolute path of the deployment scripts
export deployment_scripts_path="$script_path/../deployment-scripts"
echo "Deployment scripts path: $deployment_scripts_path"

# Get the absolute path of the sftp server template
export sftp_server_template_path="$script_path/sftp-server/sftp-server.yaml"
echo "SFTP server template path: $sftp_server_template_path"

# Get the absolute path of the code pipeline template
export code_pipeline_template_path="$script_path/code-pipeline/code-pipeline.yaml"
echo "Code pipeline template path: $code_pipeline_template_path"