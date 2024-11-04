ansible-playbook -i $1, -e ansible_user=az-user -e ansible_password=DevOps123456 -e env=dev -e app_name=$2 roboshop.yml
