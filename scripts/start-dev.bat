@echo off

set "PROJECT_DIR=%CD%"
set "PATH=%PROJECT_DIR\scripts%;%PATH%"
set "TERRAFORM_DIR=%PROJECT_DIR%\terraform"
set "KEYS_DIR=%PROJECT_DIR%\keys"
set "SCRIPTS_DIR=%~dp0"
set "SCRIPTS_DIR=%SCRIPTS_DIR:~0,-1%"

call %TERRAFORM_DIR%\set-tf-output-2-env-var.bat

echo ===== Terraform values set as env vars =====
type %TERRAFORM_DIR%\set-tf-output-2-env-var.bat

echo ===== Shortcuts =====
doskey tfa=%SCRIPTS_DIR%\tf-apply.bat
@REM doskey tfa=cd %TERRAFORM_DIR% $T echo "terraform apply" $T terraform apply  
echo tfa = Terraform apply

doskey tfd=%SCRIPTS_DIR%\tf-destroy.bat
@REM doskey tfd=cd %TERRAFORM_DIR% $T terraform destroy
echo tfd = Terraform destroy

doskey cdd=cd %PROJECT_DIR%
echo cdd = CD to project directory

doskey sshe=ssh -i %PROJECT_DIR%\keys\private_key.pem -o ServerAliveInterval=60 -o ServerAliveCountMax=180 ec2-user@%ELASTIC_IP%
echo sshe = SSH into EC2

doskey ec2=aws ec2 start-instances --instance-ids %INSTANCE_ID%
echo ec2 = Start EC2

doskey ec2x=aws ec2 stop-instances --instance-ids %INSTANCE_ID%
echo ec2x = Stop EC2

doskey neo4j=start http://%EIP_PUBLIC_DNS%:7474/
echo neo4j = Opens Neo4j in Browser

doskey portainer=start https://%EIP_PUBLIC_DNS%:6102/
echo portainer = Opens Portainer in Browser

doskey esl=%SCRIPTS_DIR%\ec2-setup-logs.bat
echo esl = See EC2 setup logs

doskey tec2=ssh-keygen -R %ELASTIC_IP% $T cd %TERRAFORM_DIR% $T terraform taint aws_instance.main_instance $T %SCRIPTS_DIR%\tf-apply.bat 
echo tec2 = Taint ec2 and destroy and recreate it

doskey rkh=ssh-keygen -R %ELASTIC_IP%  
echo rkh = Remove known SSH host

title %PROJECT_ID%

doskey sshe=ssh -i %PROJECT_DIR%\keys\private_key.pem ec2-user@%ELASTIC_IP%