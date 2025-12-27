#!/usr/bin/env ruby
# vpc_import_generator.rb

require 'aws-sdk-ec2'
require 'optparse'

class VPCImportGenerator
  def initialize(vpc_id, region: 'us-east-1', output_dir: '.')
    @vpc_id = vpc_id
    @region = region
    @output_dir = output_dir
    @ec2 = Aws::EC2::Client.new(region: region)
    @imports = []
    @terraform_blocks = []
  end

  def generate
    puts "Scanning VPC #{@vpc_id} in #{@region}..."
    
    scan_vpc
    scan_subnets
    scan_internet_gateways
    scan_nat_gateways
    scan_route_tables
    scan_security_groups
    scan_vpc_endpoints
    scan_network_acls
    
    write_output
    print_summary
  end

  private

def scan_vpc
  vpc = @ec2.describe_vpcs(vpc_ids: [@vpc_id]).vpcs.first
  
  # Get DNS attributes separately
  dns_hostnames = @ec2.describe_vpc_attribute(
    vpc_id: @vpc_id,
    attribute: 'enableDnsHostnames'
  ).enable_dns_hostnames.value
  
  dns_support = @ec2.describe_vpc_attribute(
    vpc_id: @vpc_id,
    attribute: 'enableDnsSupport'
  ).enable_dns_support.value
  
  add_import(
    "aws_vpc.main",
    @vpc_id,
    terraform_block('aws_vpc', 'main', {
      cidr_block: vpc.cidr_block,
      enable_dns_hostnames: dns_hostnames,
      enable_dns_support: dns_support,
      tags: format_tags(vpc.tags)
    })
  )
end

  def scan_subnets
    subnets = @ec2.describe_subnets(
      filters: [{ name: 'vpc-id', values: [@vpc_id] }]
    ).subnets

    subnets.each do |subnet|
      resource_name = generate_subnet_name(subnet)
      
      add_import(
        "aws_subnet.#{resource_name}",
        subnet.subnet_id,
        terraform_block('aws_subnet', resource_name, {
          vpc_id: '${aws_vpc.main.id}',
          cidr_block: subnet.cidr_block,
          availability_zone: subnet.availability_zone,
          map_public_ip_on_launch: subnet.map_public_ip_on_launch,
          tags: format_tags(subnet.tags)
        })
      )
    end
  end

  def scan_internet_gateways
    igws = @ec2.describe_internet_gateways(
      filters: [{ name: 'attachment.vpc-id', values: [@vpc_id] }]
    ).internet_gateways

    igws.each do |igw|
      add_import(
        "aws_internet_gateway.main",
        igw.internet_gateway_id,
        terraform_block('aws_internet_gateway', 'main', {
          vpc_id: '${aws_vpc.main.id}',
          tags: format_tags(igw.tags)
        })
      )
    end
  end

  def scan_nat_gateways
    nat_gws = @ec2.describe_nat_gateways(
      filter: [{ name: 'vpc-id', values: [@vpc_id] }]
    ).nat_gateways.select { |ng| ng.state == 'available' }

    nat_gws.each_with_index do |nat, idx|
      resource_name = nat_gws.size > 1 ? "nat_#{idx + 1}" : "nat"
      subnet_name = find_subnet_name(nat.subnet_id)
      
      add_import(
        "aws_nat_gateway.#{resource_name}",
        nat.nat_gateway_id,
        terraform_block('aws_nat_gateway', resource_name, {
          allocation_id: nat.nat_gateway_addresses.first.allocation_id,
          subnet_id: "${aws_subnet.#{subnet_name}.id}",
          tags: format_tags(nat.tags)
        })
      )
    end
  end

  def scan_route_tables
    route_tables = @ec2.describe_route_tables(
      filters: [{ name: 'vpc-id', values: [@vpc_id] }]
    ).route_tables

    route_tables.each do |rt|
      resource_name = generate_route_table_name(rt)
      
      add_import(
        "aws_route_table.#{resource_name}",
        rt.route_table_id,
        terraform_block('aws_route_table', resource_name, {
          vpc_id: '${aws_vpc.main.id}',
          tags: format_tags(rt.tags)
        })
      )

      # Route table associations
      rt.associations.each do |assoc|
        next if assoc.main
        next unless assoc.subnet_id
        
        subnet_name = find_subnet_name(assoc.subnet_id)
        assoc_name = "#{resource_name}_#{subnet_name}"
        
        add_import(
          "aws_route_table_association.#{assoc_name}",
          assoc.route_table_association_id,
          terraform_block('aws_route_table_association', assoc_name, {
            subnet_id: "${aws_subnet.#{subnet_name}.id}",
            route_table_id: "${aws_route_table.#{resource_name}.id}"
          })
        )
      end
    end
  end

  def scan_security_groups
    sgs = @ec2.describe_security_groups(
      filters: [{ name: 'vpc-id', values: [@vpc_id] }]
    ).security_groups

    sgs.each do |sg|
      next if sg.group_name == 'default' # Usually want to avoid managing default SG
      
      resource_name = sanitize_name(sg.group_name)
      
      add_import(
        "aws_security_group.#{resource_name}",
        sg.group_id,
        "# Security group: #{sg.group_name}\n# Note: Import separately, then add ingress/egress rules"
      )
    end
  end

  def scan_vpc_endpoints
    endpoints = @ec2.describe_vpc_endpoints(
      filters: [{ name: 'vpc-id', values: [@vpc_id] }]
    ).vpc_endpoints

    endpoints.each do |ep|
      service_name = ep.service_name.split('.').last
      resource_name = sanitize_name(service_name)
      
      add_import(
        "aws_vpc_endpoint.#{resource_name}",
        ep.vpc_endpoint_id,
        "# VPC Endpoint: #{ep.service_name}"
      )
    end
  end

  def scan_network_acls
    nacls = @ec2.describe_network_acls(
      filters: [{ name: 'vpc-id', values: [@vpc_id] }]
    ).network_acls

    nacls.each do |nacl|
      next if nacl.is_default # Usually skip default NACL
      
      resource_name = generate_nacl_name(nacl)
      add_import(
        "aws_network_acl.#{resource_name}",
        nacl.network_acl_id,
        "# Network ACL"
      )
    end
  end

  def add_import(resource_address, resource_id, terraform_block = nil)
    @imports << { address: resource_address, id: resource_id }
    @terraform_blocks << terraform_block if terraform_block
  end

  def write_output
    # Write import commands
    File.open(File.join(@output_dir, 'import_commands.sh'), 'w') do |f|
      f.puts "#!/bin/bash"
      f.puts "# Generated VPC import commands for #{@vpc_id}"
      f.puts "# Run from your Terraform directory\n\n"
      f.puts "set -e\n\n"
      
      @imports.each do |import|
        f.puts "terraform import #{import[:address]} #{import[:id]}"
      end
    end

    # Write skeleton Terraform config
    File.open(File.join(@output_dir, 'vpc_resources.tf'), 'w') do |f|
      f.puts "# Generated Terraform configuration for VPC #{@vpc_id}"
      f.puts "# Review and adjust before applying\n\n"
      @terraform_blocks.each { |block| f.puts block + "\n\n" }
    end

    File.chmod(0755, File.join(@output_dir, 'import_commands.sh'))
  end

  def print_summary
    puts "\nGeneration complete!"
    puts "  Imports:    #{@imports.size} resources"
    puts "  Output dir: #{@output_dir}"
    puts "\nFiles created:"
    puts "  - import_commands.sh  (run this to import resources)"
    puts "  - vpc_resources.tf    (skeleton Terraform config)"
    puts "\nNext steps:"
    puts "  1. Review vpc_resources.tf and adjust as needed"
    puts "  2. Run: ./import_commands.sh"
    puts "  3. Run: terraform plan (should show no changes)"
  end

  # Helper methods
  
  def terraform_block(resource_type, name, attributes)
    lines = ["resource \"#{resource_type}\" \"#{name}\" {"]
    attributes.each do |key, value|
      lines << "  #{key} = #{format_value(value)}"
    end
    lines << "}"
    lines.join("\n")
  end

  def format_value(value)
    case value
    when String
      value.start_with?('${') ? value : "\"#{value}\""
    when Hash
      format_map(value)
    when TrueClass, FalseClass
      value.to_s
    else
      value.inspect
    end
  end

  def format_map(hash)
    return '{}' if hash.empty?
    lines = ['{']
    hash.each { |k, v| lines << "    #{k} = #{format_value(v)}" }
    lines << '  }'
    lines.join("\n  ")
  end

  def format_tags(tags)
    return {} if tags.nil? || tags.empty?
    tags.each_with_object({}) { |tag, h| h[tag.key] = tag.value }
  end

  def generate_subnet_name(subnet)
    name_tag = subnet.tags&.find { |t| t.key == 'Name' }&.value
    if name_tag
      sanitize_name(name_tag)
    else
      az = subnet.availability_zone.split('-').last
      type = subnet.map_public_ip_on_launch ? 'public' : 'private'
      "#{type}_#{az}"
    end
  end

  def generate_route_table_name(rt)
    name_tag = rt.tags&.find { |t| t.key == 'Name' }&.value
    name_tag ? sanitize_name(name_tag) : "rt_#{rt.route_table_id.split('-').last}"
  end

  def generate_nacl_name(nacl)
    name_tag = nacl.tags&.find { |t| t.key == 'Name' }&.value
    name_tag ? sanitize_name(name_tag) : "nacl_#{nacl.network_acl_id.split('-').last}"
  end

  def find_subnet_name(subnet_id)
    @subnet_names ||= {}
    return @subnet_names[subnet_id] if @subnet_names[subnet_id]
    
    subnet = @ec2.describe_subnets(subnet_ids: [subnet_id]).subnets.first
    @subnet_names[subnet_id] = generate_subnet_name(subnet)
  end

  def sanitize_name(name)
    name.downcase
        .gsub(/[^a-z0-9_]/, '_')
        .gsub(/_+/, '_')
        .gsub(/^_|_$/, '')
  end
end

# CLI
options = {
  region: ENV['AWS_REGION'] || 'us-east-1',
  output_dir: '.'
}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options] VPC_ID"

  opts.on('-r', '--region REGION', 'AWS region (default: us-east-1)') do |r|
    options[:region] = r
  end

  opts.on('-o', '--output DIR', 'Output directory (default: .)') do |d|
    options[:output_dir] = d
  end

  opts.on('-h', '--help', 'Show this help') do
    puts opts
    exit
  end
end.parse!

if ARGV.empty?
  puts "Error: VPC ID required"
  puts "Usage: #{$0} [options] VPC_ID"
  exit 1
end

vpc_id = ARGV[0]
generator = VPCImportGenerator.new(vpc_id, **options)
generator.generate
