# MySQL Cheatsheets

**Install Mysql:**

```bash
sudo apt install mysql --no-install-recommends
sudo mysql_secure_installation
```

**Change Root Password:**

```sql
SELECT user,authentication_string,plugin,host FROM mysql.user;
ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY 'Password123#@!';
FLUSH PRIVILEGES;
```

**Create User:**

```sql
CREATE USER 'sha2user'@'localhost' IDENTIFIED WITH caching_sha2_password BY 'password';
```

```sql
sudo mariadb
CREATE USER 'katie'@'localhost' IDENTIFIED BY 'yourpassword';
GRANT ALL PRIVILEGES ON *.* TO 'katie'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
```

**Grant all privileges:**

```sql
GRANT ALL PRIVILEGES ON database_name TO 'user'@'hostname' IDENTIFIED BY PASSWORD <password>;
```

```sql
GRANT ALL PRIVILEGES ON *.* TO 'user'@'hostname';
```

**Flush Privileges:**

```sql
FLUSH PRIVILEGES;
```

[Source (ostechnix.com)](https://ostechnix.com/change-authentication-method-for-mysql-root-user-in-ubuntu/)
