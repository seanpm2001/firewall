#
# Cookbook Name:: firewall
# Provider:: rule_iptables
#
# Copyright 2012, computerlyrik
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
# limitations under the License.
#
class Chef
  class Provider::FirewallRuleIptables < Provider
    include Poise
    include Chef::Mixin::ShellOut
    include FirewallCookbook::Helpers
    provides :firewall_rule, :os => 'linux', :platform_family => ['rhel']

    def action_allow
      apply_rule(:allow)
    end

    def action_deny
      apply_rule(:deny)
    end

    def action_reject
      apply_rule(:reject)
    end

    def action_redirect
      apply_rule(:redirect)
    end

    def action_masquerade
      apply_rule(:masquerade)
    end

    def action_log
      apply_rule(:log)
    end

    private

    CHAIN = { :in => 'INPUT', :out => 'OUTPUT', :pre => 'PREROUTING', :post => 'POSTROUTING' } # , nil => "FORWARD"}
    TARGET = { :allow => 'ACCEPT', :reject => 'REJECT', :deny => 'DROP', :masquerade => 'MASQUERADE', :redirect => 'REDIRECT', :log => 'LOG --log-prefix "iptables: " --log-level 7' }

    def apply_rule(type = nil)
      firewall_command = 'iptables '
      if new_resource.position
        firewall_command << '-I ' # {new_resource.position} "
      else
        firewall_command << '-A '
      end

      # TODO: implement logging for :connections :packets
      firewall_rule = build_firewall_rule(type)

      Chef::Log.debug("#{new_resource}: #{firewall_rule}")
      if rule_exists?(firewall_rule)
        Chef::Log.info("#{new_resource} #{type} rule exists... won't apply")
      else
        cmdstr = firewall_command + firewall_rule
        converge_by("firewall_rule[#{new_resource.name}] #{firewall_rule}") do
          notifying_block do
            shell_out!(cmdstr) # shell_out! is already logged
            new_resource.updated_by_last_action(true)
          end
        end
      end
    end

    def build_firewall_rule(type = nil)
      if new_resource.raw
        firewall_rule = new_resource.raw.strip!
      else
        firewall_rule = ''
        if new_resource.direction
          firewall_rule << "#{CHAIN[new_resource.direction.to_sym]} "
        else
          firewall_rule << 'FORWARD '
        end
        firewall_rule << "#{new_resource.position} " if new_resource.position

        if [:pre, :post].include?(new_resource.direction)
          firewall_rule << '-t nat '
        end
        firewall_rule << "-s #{new_resource.source} " if new_resource.source && new_resource.source != '0.0.0.0/0'
        firewall_rule << "-p #{new_resource.protocol} " if new_resource.protocol
        firewall_rule << '-m tcp ' if new_resource.protocol.to_sym == :tcp

        # using multiport here allows us to simplify our greps and rule building
        firewall_rule << "-m multiport --sports #{port_to_s(new_resource.source_port)} " if new_resource.source_port
        firewall_rule << "-m multiport --dports #{port_to_s(dport_calc)} " if dport_calc

        firewall_rule << "-i #{new_resource.interface} " if new_resource.interface
        firewall_rule << "-o #{new_resource.dest_interface} " if new_resource.dest_interface
        firewall_rule << "-d #{new_resource.destination} " if new_resource.destination
        firewall_rule << "-m state --state #{new_resource.stateful.is_a?(Array) ? new_resource.stateful.join(',').upcase : new_resource.stateful.upcase} " if new_resource.stateful
        firewall_rule << "-m comment --comment \"#{new_resource.description}\" "
        firewall_rule << "-j #{TARGET[type]} "
        firewall_rule << "--to-ports #{new_resource.redirect_port} " if type == 'redirect'
        firewall_rule.strip!
      end
      firewall_rule
    end

    def rule_exists?(rule)
      fail 'no rule supplied' unless rule
      if new_resource.position
        detect_rule = rule.gsub(/#{CHAIN[new_resource.direction]}\s(\d+)/, '\1' + " -A #{CHAIN[new_resource.direction]}")
      else
        detect_rule = rule
      end

      line_number = 0
      match = shell_out!('iptables', '-S', CHAIN[new_resource.direction]).stdout.lines.find do |line|
        next if line[1] == 'P'
        line_number += 1
        line = "#{line_number} #{line}" if new_resource.position
        # Chef::Log.debug("matching: [#{detect_rule}] to [#{line.chomp.rstrip}]")
        line =~ /#{detect_rule}/
      end

      match
    rescue Mixlib::ShellOut::ShellCommandFailed
      Chef::Log.debug("#{new_resource} check fails with: " + cmd.inspect)
      Chef::Log.debug("#{new_resource} assuming #{rule} rule does not exist")
      false
    end

    def dport_calc
      new_resource.dest_port || new_resource.port
    end
  end
end
