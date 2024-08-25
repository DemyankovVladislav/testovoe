Задача 1: BASH скрипт для развертывания стека

Для запуска скрипта task1_bash/lamp.sh (нужно задать свои переменные в файле .env и запустить скрипт под sudo) - я бы использовал Ansible или docker-compose для этой задачи.

Задача 2: Реализация через Ansible
Для запуска плейбука task2_ansible/common.yml (нужно добавить свой токен и чат_ид Telegram) этот этап улучшил бы с помощью ansible-vault;
ansible-playbook common.yml -e "web_server=nginx" -vv или (web_server=haproxy) и в дальнейшем бы добавлял необходимые роли и указывал в переменной значения.
Этот инструмент бы и использовал, но если нужна будет масштабируемость и отказоустойчивость выбрал бы k8s/helm или облачные решения.

Задача 3: Контейнеризация на базе Docker и Podman

Сделал базовый docker-compose.yml (nginx+mysql+wordpress+joomla) по поводу улучшений: это certbot для сертификатов + второй docker-compose (например) для мониторинга prometheus/blackbox exporter/grafana/alertmanager.
