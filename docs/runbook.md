## Запуск сети

# Docker (Ubuntu/Debian)
curl -fsSL https://get.docker.com | bash
sudo usermod -aG docker $USER    # после этого перелогиньтесь

# Containerlab
bash -c "$(curl -sL https://get.containerlab.dev)"

# Проверка
docker --version
containerlab version

# Вариант установки №2 (Всё разом)
curl -sL https://containerlab.dev/setup | sudo -E bash -s "all"



# Создайте папку "lab1"
mkdir lab1
cd lab1

# Загрузите из репозитория папку "configs"
git pull

# Создайте файл "lab1.clab.yml"
touch lab1.clab.yml

Структура папок должна получиться следующая:
```
lab1/
├── lab1.clab.yml       
└── configs/
    ├── leaf1/
    │   ├── frr.conf
    │   ├── daemons
    │   └── setup.sh
    └── leaf2/
        ├── frr.conf
        ├── daemons
        └── setup.sh
```
# Из папки "lab1" запустите ContainerLab
sudo containerlab deploy -t lab1.clab.yml

# Отключить лабу
sudo containerlab destroy -t lab1.clab.yml 

# Перезапуск leaf1
sudo clab restart -t lab1.clab.yml leaf1


## Проверка работоспособности

# Cтатус лабы
sudo containerlab inspect -t lab1.clab.yml   

# Зайти в CLI(FRR) маршрутизатора 
docker exec -it clab-lab1-leaf1 vtysh

# Вывести таблицу VNI на leaf1, убедиться что MAC'и/ARP'ы изучаются
docker exec clab-lab1-leaf1 vtysh -c "show evpn vni"
docker exec clab-lab1-leaf1 vtysh -c "show bgp l2vpn evpn summary"

# Вывести глобальную таблицы маршрутизации VRF убедиться, что есть маршруты и ECMP
docker exec clab-lab1-leaf1 vtysh -c "show ip route"
docker exec clab-lab1-leaf1 vtysh -c "show ip route vrf CUST-BD"
docker exec clab-lab1-leaf1 vtysh -c "show ip route vrf CUST-WEB"

# Проверить, что серверу доступен шлюз
docker exec -it clab-lab1-server1 ping 10.10.20.254

# Проверка прохождения трафика от сервера к серверу в одном L2VNI
docker exec -it clab-lab1-server4 ping 10.10.10.5 

# Проверка прохождения трафика от сервера к серверу в разных L2VNI
docker exec -it clab-lab1-server4 ping 10.10.20.1 

# Проверка Anycast Gateway
docker exec -it clab-lab1-server5 arp | grep 10.10.10.254
docker exec -it clab-lab1-server4 arp | grep 10.10.10.254
Ожидается одинаковый MAC-адрес на выводе

# Проверка TC. Запускаем пинг с DSCP 10 и смотрим статистику по классам
docker exec -it clab-lab1-server4 ping -Q 0x28 -c 10 10.10.10.5
docker exec -it clab-lab1-leaf2 tc -s filter show dev eth2 parent 1:
Ожидается вывод с задаными фильтрами и строка "(success Х )", где Х - кол-во пакетов 