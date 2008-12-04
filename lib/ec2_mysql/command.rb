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
require 'optparse'
require 'json'
require File.join(File.dirname(__FILE__), "db")
require File.join(File.dirname(__FILE__), "ec2")
require File.join(File.dirname(__FILE__), "log")

class Ec2Mysql
  class Command
    
    attr_accessor :aws_access_key, :aws_secret_key, :mysql_username, 
                  :mysql_password, :mysql_host, :instance_id, :volume_id,
                  :to_keep, :log_level
    
    def initialize(args)
      @aws_access_key = nil
      @aws_secret_key = nil
      @mysql_username = "root"
      @mysql_password = nil
      @mysql_rep_username = nil
      @mysql_rep_password = nil
      @mysql_host = nil
      @mysql_start_replication = true
      @instance_id = nil
      @volume_id = nil
      @to_keep = 2
      @device = "/dev/sdh"
      @kernel_device = "/dev/sdh"
      @mount_point = "/mnt/mysql"
      @mysql_start = "/etc/init.d/mysql start"
      @log_level = :info
      
      opts = OptionParser.new do |opts|
        opts.banner = "Usage: #{$0} (options) [master|slave]"
        opts.on("-a AWS_ACCESS_KEY", "--aws-access-key AWS_ACCESS_KEY", "Your AWS Access Key") do |a|
          @aws_access_key = a
        end
        opts.on("-s AWS_SECRET_KEY", "--aws-secret-key AWS_SECRET_KEY", "Your AWS Secret Key") do |s|
          @aws_secret_key = s
        end
        opts.on("-i INSTANCE_ID", "--instance-id INSTANCE_ID", "Ec2 Instance ID") do |i|
          @instance_id = i
        end
        opts.on("-v VOLUME_ID", "--volume-id VOLUME_ID", "EBS Volume ID") do |v|
          @volume_id = v
        end
        opts.on("-k TO_KEEP", "--to-keep TO_KEEP", "Number of Snapshots to Keep (default 2)") do |k|
          @to_keep = k
        end
        opts.on("-d DEVICE", "--device DEVICE", "The raw block device to expose a new EBS on for slaves (default /dev/sdh)") do |d|
          @device = d
        end
        opts.on("-r KERNELDEVICE", "--kernel-device KERNELDEVICE", "The device as seen by the kernel (for mounting)") do |k|
          @kernel_device = k
        end
        opts.on("-m MOUNT", "--mount MOUNT", "The mount point for a new EBS slave") do |m|
          @mount_point = m
        end
        opts.on("-u MYSQL_USER", "--username MYSQL_USER", "MySQL Username (default root)") do |u|
          @mysql_username = u
        end
        opts.on("-p MYSQL_PASS", "--password MYSQL_PASS", "MySQL Password") do |p|
          @mysql_password = p
        end
        opts.on("-h MYSQL_HOST", "--hostname MYSQL_HOST", "MySQL Server Hostname (default socket)") do |h|
          @mysql_host = h
        end
        opts.on("-U MYSQL_REP_USER", "--replication-username MYSQL_REP_USER", "MySQL Username for replication") do |u|
          @mysql_rep_username = u
        end
        opts.on("-P MYSQL_REP_PASS", "--replication-password MYSQL_REP_PASS", "MySQL Password for replication") do |p|
          @mysql_rep_password = p
        end
        opts.on("-c MYSQL_START", "--mysql-start MYSQL_START", "MySQL Start command") do |c|
          @mysql_start = c
        end
        opts.on("-n", "--no-replication", "Do not start MySQL replication") do |n|
          @mysql_start_replication = false
        end
        opts.on_tail("-l LEVEL", "--loglevel LEVEL", "Set the log level (debug, info, warn, error, fatal)") do |l|
          @log_level = l.to_sym
        end
        opts.on_tail("-h", "--help", "Show this message") do
          puts opts
          exit
        end
      end
      action = opts.parse!(args)
      Ec2Mysql::Log.level(@log_level)
      
      unless action.length == 1
        puts "You must supply an action (only one!): master or slave" 
        puts opts
        exit 100
      end
      
      @action = action[0]
      
      unless @action == "master" || @action == "slave"
        puts "You must supply master or slave - you supplied #{@action}"
        puts opts
        exit 100
      end

      @ec2 = Ec2Mysql::EC2.new(@aws_access_key, @aws_secret_key, @instance_id, @volume_id)
    end
    
    def run
      case @action
      when "master"
        self.master
      when "slave"
        self.slave
      end
    end
    
    def master
      @ec2.get_instance_id
      @ec2.find_volume_id
      @ec2.manage_snapshots(@to_keep, @volume_id)
      @db = Ec2Mysql::DB.new(@mysql_username, @mysql_password, @mysql_host)
      @db.flush_tables_with_read_lock
      master_status = @db.show_master_status
      ms_json = File.open(File.join(@mount_point, "master_status.json"), "w")
      JSON.dump(master_status, ms_json)
      ms_json.close
      @ec2.create_snapshot
      @db.unlock_tables
      @db.disconnect
    end
    
    def slave
      raise "You must supply -v,--volume-id to bootstrap the slave from" unless @volume_id
      raise "You must supply -h,--mysql-host to configure the master" unless @mysql_host
      raise "You must supply -U,--mysql-rep-username to configure the master" unless @mysql_rep_username
      raise "You must supply -P,--mysql-rep-password to configure the master" unless @mysql_rep_password
      
      @ec2.get_instance_id
      @ec2.get_availability_zone
      @ec2.get_volume_size
      @ec2.find_snapshot_id
      @ec2.create_volume
      @ec2.attach_volume(@device)
      system("mount #{@kernel_device} #{@mount_point}")
      system(@mysql_start)
      if @mysql_start_replication
        json_file = File.open(File.join(@mount_point, "master_status.json"))
        master_status = JSON.load(json_file)
        json_file.close
        master_status["master_host"] = @mysql_host
        master_status["master_user"] = @mysql_rep_username
        master_status["master_password"] = @mysql_rep_password
        @db = Ec2Mysql::DB.new(@mysql_username, @mysql_password, @mysql_host)
        @db.change_master(master_status)
        @db.slave_start
      end
    end
    
  end
end
