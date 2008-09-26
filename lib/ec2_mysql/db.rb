#
# Author:: Adam Jacob (<adam@hjksolutions.com>)
# Copyright:: Copyright (c) 2008 HJK Solutions, LLC
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License

require 'rubygems'
require 'dbi'
require File.join(File.dirname(__FILE__), "log")

class Ec2Mysql
  class DB
    
    attr_accessor :dbh
    
    def initialize(username, password, hostname=nil)
      @username = username
      @password = password
      @hostname = hostname
      Ec2Mysql::Log.debug("Connecting to MySQL")
      @dbh = DBI.connect("DBI:Mysql:mysql", username, password)
    end
    
    def show_master_status
      status = Hash.new
      @dbh.select_all("show master status") do |row|
        row.each_with_name do |v, column|
          status[column] = v
        end
      end
      Ec2Mysql::Log.debug("Master status: #{status.inspect}")
      status
    end
    
    def change_master(master_status)
      command = "CHANGE MASTER TO"
      command += " MASTER_HOST='#{master_status['master_host']}',"
      command += " MASTER_USER='#{master_status['master_user']}',"
      command += " MASTER_PASSWORD='#{master_status['master_password']}',"
      command += " MASTER_LOG_FILE='#{master_status['File']}',"
      command += " MASTER_LOG_POS=#{master_status['Position']}"
      Ec2Mysql::Log.debug(command)
      @dbh.do(command)
      Ec2Mysql::Log.info("Master is now #{master_status['master_host']} at #{master_status['File']} pos #{master_status['Position']}")
    end
    
    def slave_start
      @dbh.do("slave start")
      Ec2Mysql::Log.info("Slave started")
    end
    
    def flush_tables_with_read_lock
      Ec2Mysql::Log.debug("Flushing tables with read lock")
      @dbh.do("flush tables with read lock")
      true
    end
    
    def unlock_tables
      Ec2Mysql::Log.debug("Unlocking tables")
      @dbh.do("unlock tables")
      true
    end
    
    def disconnect
      Ec2Mysql::Log.debug("Disconnecting from MySQL")
      @dbh.disconnect
    end
    
  end
end
