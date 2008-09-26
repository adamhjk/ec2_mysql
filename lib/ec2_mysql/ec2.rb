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
require 'right_aws'
require 'open-uri'
require File.join(File.dirname(__FILE__), 'log')

class Ec2Mysql
  class EC2
    
    attr_accessor :ec2, :instance_id, :volume_id, :availability_zone
    
    def initialize(aws_access_key, aws_secret_key, instance_id=nil, volume_id=nil)
      @aws_access_key = aws_access_key
      @aws_secret_key = aws_secret_key
      @instance_id = instance_id
      @volume_id = volume_id
      @availability_zone = nil
      Ec2Mysql::Log.debug("Connecting to EC2")
      @ec2 = RightAws::Ec2.new(aws_access_key, aws_secret_key, { :logger => Ec2Mysql::Log })
    end
    
    def get_instance_id
      return @instance_id if @instance_id
      
      open('http://169.254.169.254/latest/meta-data/instance-id') do |f|
        @instance_id = f.gets
      end
      raise "Cannot find instance id!" unless @instance_id
      Ec2Mysql::Log.debug("Instance ID is #{@instance_id}")
      @instance_id
    end
    
    def get_availability_zone
      return @availability_zone if @availability_zone
      
      open('http://169.254.169.254/latest/meta-data/placement/availability-zone/') do |f|
        @availability_zone = f.gets
      end
      raise "Cannot find availability zone!" unless @availability_zone
      Ec2Mysql::Log.debug("Availability zone is #{@availability_zone}")
      @availability_zone
    end
    
    def find_volume_id
      return @volume_id if @volume_id
      
      @ec2.describe_volumes.each do |volume|
        if volume[:aws_instance_id] == @instance_id
          @volume_id = volume[:aws_id]
        end
      end
      raise "Cannot find volume id!" unless @volume_id
      Ec2Mysql::Log.debug("Volume ID is #{@volume_id}")
      @volume_id
    end
    
    def get_volume_size
      @ec2.describe_volumes.each do |volume|
        if volume[:aws_id] == @volume_id
          @volume_size = volume[:aws_size]
        end
      end
      Ec2Mysql::Log.debug("Volume #{@volume_id} size is #{@volume_size}")
      @volume_size
    end
    
    def find_snapshot_id
      return @snapshot_id if @snapshot_id
      
      @ec2.describe_snapshots.sort { |a,b| b[:aws_started_at] <=> a[:aws_started_at] }.each do |snapshot|
        if snapshot[:aws_volume_id] == @volume_id
          @snapshot_id = snapshot[:aws_id]
        end
      end
      raise "Cannot find snapshot id!" unless @snapshot_id
      Ec2Mysql::Log.debug("Snapshot ID is #{@snapshot_id}")
      @snapshot_id
    end
    
    def manage_snapshots(to_keep=2, volume_id=nil)
      volume_id ||= @volume_id
      old_snapshots = Array.new
      @ec2.describe_snapshots.sort { |a,b| b[:aws_started_at] <=> a[:aws_started_at] }.each do |snapshot|
        if snapshot[:aws_volume_id] == volume_id
          old_snapshots << snapshot
        end 
      end
      if old_snapshots.length >= to_keep 
        old_snapshots[to_keep - 1, old_snapshots.length].each do |die|
          Ec2Mysql::Log.info("Deleting old snapshot #{die[:aws_id]}")
          @ec2.delete_snapshot(die[:aws_id])
        end
      end
    end
    
    def create_snapshot(volume_id=nil)
      volume_id ||= @volume_id
      snap = @ec2.create_snapshot(volume_id)
      Ec2Mysql::Log.info("Created snapshot of #{volume_id} as #{snap[:aws_id]}")
      snap
    end
    
    def create_volume(snapshot_id=nil, size=nil, availability_zone=nil)
      snapshot_id ||= @snapshot_id
      size ||= @volume_size
      availability_zone ||= @availability_zone
  
      nv = @ec2.create_volume(snapshot_id, size, availability_zone)
      Ec2Mysql::Log.info("Created new volume #{nv[:aws_id]} based on #{snapshot_id}")
      
      creating = true
      while creating
        status = @ec2.describe_volumes
        status.each do |volume|
          if volume[:aws_id] == nv[:aws_id]
            case volume[:aws_status]
            when "in-use","available"
              Ec2Mysql::Log.debug("Volume is available")
              creating = false
            else
              Ec2Mysql::Log.debug("Volume is #{volume[:aws_status]}")
            end
          end
        end
        sleep 3
      end
      @slave_volume = nv[:aws_id]
    end
    
    def attach_volume(device)
      status = @ec2.attach_volume(@slave_volume, @instance_id, device)
      Ec2Mysql::Log.debug("Attaching #{@slave_volume} as #{device}")
      creating = true
      while creating
        status = @ec2.describe_volumes
        status.each do |volume|
          if volume[:aws_id] == @slave_volume
            case volume[:aws_status]
            when "in-use"
              Ec2Mysql::Log.debug("Volume is attached")
              creating = false
            else
              Ec2Mysql::Log.debug("Volume is #{volume[:aws_status]}")
            end
          end
        end
        sleep 3
      end
      true
    end
    
    
  end
end