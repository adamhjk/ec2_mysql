= Ec2Mysql

== DESCRIPTION:

Simplifies setting up new MySQL slaves using EC2 with Elastic Block Devices

== FEATURES/PROBLEMS:

* Snapshot a master with slave creation information saved as JSON
  * Keep N backups
* Create a slave from a given snapshot (or the latest, given a Volume ID)
  * Deal with both regular and LVM block devices
  
== SYNOPSIS:

It's a two step process.  Run the backup on the Master, then run the build on your Slave.

=== Master Backup:

On your master EC2 Node:
	$ sudo ./ec2_mysql -a 'AWS_ID' -s 'AWS_SECRET_KEY' -p 'MYSQL_ROOT' master

=== Slave Creation:

On your slave EC2 Node:

  $ sudo ./ec2_mysql -a 'AWS_ID' -s 'AWS_SECRET_KEY' -U 'MYSQL_REPL_USER' -P 'MYSQL_REPL_PASS' -p 'MYSQL_ROOT' -h 'MYSQL_MASTER_IP_ADDRESS' -v 'MYSQL_MASTER_EBS_VOLUME_ID' slave

== REQUIREMENTS:

* DBI
* DBD::Mysql
* Right AWS
* JSON

== INSTALL:

Haven't made a gem yet or any packages. :)

== BONUS POINTS:

Use Capistrano to dynamically build 100 slaves at the same time.  Watch magic scaling.  Celebrate.

== LICENSE:

See the LICENSE file, but:

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License

