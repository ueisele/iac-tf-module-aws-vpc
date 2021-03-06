######
# VPC
######

/* Creates a VPC in the region specified for the provider
 * https://www.terraform.io/docs/providers/aws/r/vpc.html
 * https://docs.aws.amazon.com/de_de/vpc/latest/userguide/what-is-amazon-vpc.html
 */
resource "aws_vpc" "this" {
    cidr_block = "${var.cidr}"
    assign_generated_ipv6_cidr_block = true

    instance_tenancy = "default"
    enable_dns_support = true
    enable_dns_hostnames = true

    tags = "${merge(map("Name", format("%s", var.name), "Unit", var.name), var.tags, var.vpc_tags)}"
}

######
# Subnets
######

/*
 * Subnet which is publicly available through an Internet getway
 * https://www.terraform.io/docs/providers/aws/r/subnet.html
 * https://www.terraform.io/docs/configuration/interpolation.html
 * https://docs.aws.amazon.com/de_de/vpc/latest/userguide/VPC_Internet_Gateway.html
 */
resource "aws_subnet" "public" {
    count = "${length(data.aws_availability_zone.availability_zones.*.name)}"

    vpc_id            = "${aws_vpc.this.id}"
    availability_zone = "${element(data.aws_availability_zone.availability_zones.*.name, count.index)}"
    cidr_block        = "${cidrsubnet(aws_vpc.this.cidr_block, var.subnet_cidr_newbits, count.index)}"
    ipv6_cidr_block   = "${cidrsubnet(aws_vpc.this.ipv6_cidr_block, var.subnet_ipv6_cidr_newbits, count.index)}"
    
    map_public_ip_on_launch = true
    assign_ipv6_address_on_creation = true

    tags = "${merge(map("Name", format("%s-${var.public_subnet_suffix}", var.name), "Unit", var.name), var.tags, var.public_subnet_tags)}"
}

/*
 * Subnet which is not publicly available but can access the internet through a NAT gateway (IPv4) and an Egress only Internet gateway (IPv6)
 * https://www.terraform.io/docs/providers/aws/r/subnet.html
 * https://www.terraform.io/docs/configuration/interpolation.html
 * https://docs.aws.amazon.com/de_de/vpc/latest/userguide/vpc-nat-gateway.html
 * https://docs.aws.amazon.com/de_de/vpc/latest/userguide/egress-only-internet-gateway.html 
 */
resource "aws_subnet" "protected" {
    count = "${length(data.aws_availability_zone.availability_zones.*.name)}"

    vpc_id            = "${aws_vpc.this.id}"
    availability_zone = "${element(data.aws_availability_zone.availability_zones.*.name, count.index)}"
    cidr_block        = "${cidrsubnet(aws_vpc.this.cidr_block, var.subnet_cidr_newbits, count.index + length(data.aws_availability_zone.availability_zones.*.name))}"
    ipv6_cidr_block   = "${cidrsubnet(aws_vpc.this.ipv6_cidr_block, var.subnet_ipv6_cidr_newbits, count.index + length(data.aws_availability_zone.availability_zones.*.name))}"
    
    map_public_ip_on_launch = true
    assign_ipv6_address_on_creation = true

    tags = "${merge(map("Name", format("%s-${var.protected_subnet_suffix}", var.name), "Unit", var.name), var.tags, var.protected_subnet_tags)}"
}

/*
 * Subnet which is completely private and therefore cannot access the internet
 * https://www.terraform.io/docs/providers/aws/r/subnet.html
 * https://www.terraform.io/docs/configuration/interpolation.html
 */
resource "aws_subnet" "private" {
    count = "${length(data.aws_availability_zone.availability_zones.*.name)}"

    vpc_id            = "${aws_vpc.this.id}"
    availability_zone = "${element(data.aws_availability_zone.availability_zones.*.name, count.index)}"
    cidr_block        = "${cidrsubnet(aws_vpc.this.cidr_block, var.subnet_cidr_newbits, count.index + 2 * length(data.aws_availability_zone.availability_zones.*.name))}"
    ipv6_cidr_block   = "${cidrsubnet(aws_vpc.this.ipv6_cidr_block, var.subnet_ipv6_cidr_newbits, count.index + 2 * length(data.aws_availability_zone.availability_zones.*.name))}"
    
    map_public_ip_on_launch = true
    assign_ipv6_address_on_creation = true

    tags = "${merge(map("Name", format("%s-${var.private_subnet_suffix}", var.name), "Unit", var.name), var.tags, var.private_subnet_tags)}"
}

###################
# Internet Gateway
###################
/*
 * The Internet gateway, which enables access to the public subnets from the internet
 * https://docs.aws.amazon.com/de_de/vpc/latest/userguide/VPC_Internet_Gateway.html
 * https://www.terraform.io/docs/providers/aws/r/internet_gateway.html
 */
resource "aws_internet_gateway" "this" {
  vpc_id = "${aws_vpc.this.id}"

  tags = "${merge(map("Name", format("%s", var.name), "Unit", var.name), var.tags, var.igw_tags)}"
}

/*
 * Gateway for egress IPv6 communication
 * https://docs.aws.amazon.com/de_de/vpc/latest/userguide/egress-only-internet-gateway.html
 * https://www.terraform.io/docs/providers/aws/r/egress_only_internet_gateway.html
 */
resource "aws_egress_only_internet_gateway" "this" {
  vpc_id = "${aws_vpc.this.id}"
}

################
# Publiс routes
################
/*
 * Route table for the public subnets
 * https://www.terraform.io/docs/providers/aws/r/route_table.html
 */
resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.this.id}"

  tags = "${merge(map("Name", format("%s-${var.public_subnet_suffix}", var.name), "Unit", var.name), var.tags, var.public_route_table_tags)}"
}

/*
 * Default route for IPv4 traffic which enables internet access
 * https://www.terraform.io/docs/providers/aws/r/route.html
 */
resource "aws_route" "public_internet_gateway_ipv4" {
  route_table_id         = "${aws_route_table.public.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.this.id}"
}

/*
 * Default route for IPv6 traffic which enables internet access
 * https://www.terraform.io/docs/providers/aws/r/route.html
 */
resource "aws_route" "public_internet_gateway_ipv6" {
  route_table_id         = "${aws_route_table.public.id}"
  destination_ipv6_cidr_block = "::/0"
  gateway_id             = "${aws_internet_gateway.this.id}"
}

################
# Publiс routes subnet association
################
/*
 * Associate the public route table with the public subnets
 * https://www.terraform.io/docs/providers/aws/r/route_table_association.html
 */
resource "aws_route_table_association" "public" {
    count = "${length(data.aws_availability_zone.availability_zones.*.name)}"

    subnet_id = "${element(aws_subnet.public.*.id, count.index)}"
    route_table_id = "${aws_route_table.public.id}"
}