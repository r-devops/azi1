default:
	@git pull &>/dev/null
	ansible-playbook -i $(app_name)-$(env).rdevopsb81.online, -e ansible_user=ec2-user -e ansible_password=DevOps321 -e env=$(env) -e app_name=$(app_name) roboshop.yml


