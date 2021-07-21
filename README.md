# Email Security Gateway
The project to build a Email Security Gateway (MailScanner & MailWatch) Docker image based on Rocky Linux 8.
Check out the prebuilt image on Docker Hub: https://hub.docker.com/r/iwayvietnam/esg

## Requirement
A mail server already exists and permit connection port 25 from esg to mail server

### How to start a new Email Security Gateway container from prebuilt Docker image
Assumption: A mail server already exists with ip 192.168.100.23 and domain is iwaytest2.com, ...

```bash
$ docker run --name esg --hostname esg.iwaytest2.com -d -it \
-p 25:25/tcp -p 90:90/tcp -p 7790:7790/tcp \
-v /opt/esg-docker/databases:/var/lib/mysql \
-v /opt/esg-docker/config/mailscanner:/etc/MailScanner \
-v /opt/esg-docker/config/postfix:/etc/postfix \
-v /opt/esg-docker/logs:/var/log/ \
-e DOMAIN=iwaytest2.com -e HOSTNAME=esg.iwaytest2.com \
-e POLICYDPASS=Policydpass123 -e MAILSCANNERPASS=Mailscannerpass123 \
-e MAILWATCHPASS=Mailwatchpass123 -e MAILBACKEND_HOST=192.168.100.23 iwayvietnam/esg
```
(and WAIT... 35-40 minutes)

Login GUI MailWatch:
 - URL: http://esg.iwaytest2.com:90
 - User: admin
 - Password: Mailwatchpass123
  
### How to build a new Docker image
##### Firstly, of course, install Docker and setup to manage Docker as a non-root user
See: https://docs.docker.com/engine/install/

##### Pull the latest Rocky Linux based docker image
```bash
$ docker pull rockylinux/rockylinux
```
##### Checkout this git repo
```bash
$ git clone https://github.com/iwayvietnam/esg-docker.git && cd esg-docker
```

##### Build Zimbra a new docker image
```bash
$ docker build --rm -t iwayvietnam/esg .
```

### How to start with Docker compose
##### Require : Install docker-compose for your server
```bash
$ git clone https://github.com/iwayvietnam/esg-docker.git && cd esg-docker
```
##### Edit variable in docker-compose.yml then run docker-compose
Assumption: A mail server already exists with ip 192.168.100.23 and domain is iwaytest2.com, ...

```bash
$ docker-compose up -d
```
(and WAIT... 35-40 minutes)

Login GUI MailWatch:
 - URL: http://esg.iwaytest2.com:90
 - User: admin
 - Password: Mailwatchpass123

##### Command check status
```bash
$ docker-compose status
```
##### Command check logs
```bash
$ docker-compose logs -f
```

### LICENSE
This work is released under GNU General Public License v3 or above.
