#!/usr/bin/perl
#
# Inserts "reg" (register) at appropriate lines in the
# module I/O declaration and internal wires
# when a procedural assignment is used for that net as the output
# Otherwise, the Verilog compiler will complain that the
# assignment statement cannot be used in this context

# Note: written as a hack. Many assumptions made about file layout
# 1. May not understand commented lines or comment blocks at all
# 2. Not guaranteed to work for buses or 2-D arrays
# 3. Will not work with split lines
# 4. signals of type "inout" are not supported
# 5. Only simple signal assignments are supported (A = B). No complex
#    assignments like A = B | C
# 6. assignment statements need to be on their own lines
#    eg: if (...)  a = b;   won't work

# Sujay Phadke, (C) 2017

use strict;
use warnings;
use File::Slurp;

use Term::ANSIColor;
my $COLORTERM = 1;

my $inpfile;
#my $outfile;
my @inpLines;

my %IOHash;
my %NetsHash;
my %checkedNets;

my @ModDecl;
my @IntNets;

my $ModDeclErrors;
my $IntNetsErrors;
my $TrailingComma;

if (scalar (@ARGV == 0)){
	print_err("\nNo input file specified!\n");
	exit 1;
}

my $VERIN = $ARGV[0];

open ($inpfile, "<", $VERIN) or die $!;

# read in entire file
@inpLines = read_file($inpfile);

close $inpfile;

BuildIOHash();

if ($TrailingComma == 1){
	print_err("\nModule declaration possibly contains an erroneous trailing comma!\n");
}

ParseProcedures();

if (($ModDeclErrors > 0) || ($IntNetsErrors > 0)){
	PrintOutput();
}
else{
	print_color("\nNo Errors found!\n", 'cyan');
}

exit 0;


# Assume ANSI-C style declaration within Verilog
sub BuildIOHash{
	my $flag;
	my $net;
	my $present;
	
	$flag = 0;
	$TrailingComma = 0;
	foreach(@inpLines){
		# Module declaration starts with the keyword "module"
		if (($flag == 0) && (m/module/)){
			$flag = 1;
			push @ModDecl, $_;
			next;
		}
		# Module declaration must end with ");"
		# NOTE: Assume that this termination is on it's own line
		elsif (($flag == 1) && (m/\);/)){
			$flag = 2;
			push @ModDecl, ");\n";
		}
		
		# Skip commented lines
		if (m/^\s*\/\//){
			next;
		}
		
		if ($flag == 1){
			push @ModDecl, $_;
		}
		
		# Inside Verilog module declaration. 
		# NOTE: Assume top-level module is the first module declared
		# Check for output signals
		# keep a track if it is already defined as "reg"
		# Note: Even if "reg" is grouped as an optional ()?
		# (because it may or may not exist), the count of the groups don't change
		# if it's not present. The net name will always be in $2
		# and $1 will be empty if "reg" is not present
		if (($flag == 1) && (m/\s*(?:output)\s+(reg)?\s*(?:\[.*\])?\s*(.*)/)){
			# make sure $1 and $2 are stored in some variables
			# before doing other operations
			$present = (defined $1) ? 1 : 0;
			$net = $2;

			# Remove \r,\n and trailing comma, if present
			# note: the last line inside the  module declaration
			# will not have the comma. Hence we can't include it in the regex above
			$net =~ s/[\r\n]+$//;
			$TrailingComma = $net =~ s/,//;

			$IOHash{$net} = $present;
			
		}
		
		# Check for input signals
		# Note: "inout" is skipped for now
		if (($flag == 1) && (m/\s*(?:input)\s+(?:\[.*\])?\s*(.*)/)){
			# make sure $1 and $2 are stored in some variables
			# before doing other operations
			$net = $1;

			# Remove \r,\n and trailing comma, if present
			# note: the last line of module declaration will not have the comma
			$net =~ s/[\r\n]+$//;
			$TrailingComma = $net =~ s/,//;

			$IOHash{$net} = 0;
		}
		
		# Outside module
		# Parse internal nets (wire or reg)
		# Will stop parsing name at the semi-colon
		if (($flag == 2) && (m/\s*(reg|wire)\s+(?:\[.*\])?\s*(.*);/)){
			# make sure $1 and $2 are stored in some variables
			# before doing other operations
			$present = ($1 eq "reg") ? 1 : 0;
			$net = $2;
			# Remove last char and trailing semi-colon, if present
			$net =~ s/[\r\n]+$//;
			$net =~ s/;//;
			$NetsHash{$net} = $present;
			push @IntNets, $_;
			#print "\nNet: $net  is  a reg: $present";
		}
				
	} # end foreach
	
		
	
}

sub ParseProcedures{
	my $flag;
	my $lvalue;
	my $rvalue;
	my $rvalue2;
	
	$flag = 0;
	$ModDeclErrors = 0;
	$IntNetsErrors = 0;
	
	foreach(@inpLines){
		# Procedural blocks keywords
		# http://verilog.renerta.com/mobile/source/vrg00036.htm
		
		# NOTE: 1-liners without begin/end are skipped
		if (($flag == 0) && (m/(always|initial)/)){
			$flag = 1;
			next;
		}
		
		# Assume "begin" and "end" keywords are on their own lines
		if (($flag == 1) && (m/begin/)){
			$flag = 2;
			next;
		}
		
		# after reaching "end" reset flag to continue
		# parsing for following blocks
		if (($flag == 2) && (m/end/)){
			$flag = 0;
			next;
		}
		
		# Skip commented lines
		if (m/^\s*\/\//){
			next;
		}
		
		# Inside procedure.
		# assignment statement will stop reading the line at the semi-colon
		# lvalue and rvalue: use \w+ instead of .+ so that we capture only simple nets and
		# not complex expressions like netA + netB
		if (($flag == 2) && (m/\s*(\w+?)\s*=\s*(.+?);/)){
			$lvalue = $1;
			$rvalue = $2;
			
			# Make sure rvalue is only of a simple type (words) and
			# not complex (expressions)
			# We can't use (\w+?) above directly, since we do want
			# to match the lvalue even if rvalue is complex
			if ($2 =~ m/(\w+)/){
				if ($1 ne $rvalue){
					$rvalue = "";
				}
			}
			else{
				$rvalue = "";
			}
			
			
			$checkedNets{$lvalue}++;
			if ($rvalue ne ""){
				$checkedNets{$rvalue}++;
			}
			
			# Check if lvalue is declared as a module output reg or an internal reg
			if (exists $NetsHash{$lvalue}){
				if ($NetsHash{$lvalue} != 1){
					print_color("\nlvalue: $lvalue needs to be declared as an internal reg", 'green');
					foreach (@IntNets){
						if (m/wire\s+(?:\[.*\])?\s*$lvalue/){
							s/wire/reg/;
						}
					}
					
					$ModDeclErrors++;
					
				}
				else{
					print "\nlvalue: $lvalue is correctly declared as a reg internally";
				}
			}
			elsif (exists $IOHash{$lvalue}){
				if ($IOHash{$lvalue} != 1){
					print_color("\nlvalue: $lvalue needs to be a reg in the module declaration", 'yellow');
					foreach (@ModDecl){
						if (m/output\s+(?:\[.*\])?\s*$lvalue/){
							s/output/output reg/;
						}
					}
					
					$IntNetsErrors++;
				}
				else{
					print "\nlvalue: $lvalue is correctly declared as a reg in the module declaration";
				}
			}
			else{
				print_color("\nlvalue: $lvalue not declared as an output or internet net!", 'red');
				print_color("\nAssuming it to be an internal reg and adding it in. Check size, etc.", 'red');
				push @IntNets, "reg $lvalue;\t\t// Check size\n";
				
				# Add the net to the nets hash so that it won't be duplicate if another
				# assign statement is present with the same net
				$NetsHash{$lvalue} = 1;
				$IntNetsErrors++;
			}
			
			# Rvalue may exist as an interal wire or module input
			# If not present, mark as an error and include it in the
			# nets hash as a 'wire'
			if ($rvalue ne ""){
				if ((exists $NetsHash{$rvalue}) || exists $IOHash{$rvalue}){
					print "\nrvalue: $rvalue is correctly declared internally";
				}
				else{
					print_color("\nrvalue: $rvalue needs to be declared", 'magenta');
					print_color("\nAssuming it to be an internal wire and adding it in. Check size, etc.", 'magenta');
					
					push @IntNets, "wire $rvalue;\t\t// Check size\n";
					
					# Add the net to the nets hash so that it won't be duplicate if another
					# assign statement is present with the same net
					$NetsHash{$rvalue} = 0;
					$IntNetsErrors++;
				}
			}
		}
	} # end foreach
			
}

sub PrintOutput{
	print "\n";
	print_color("\nCorrected Module declaration and Internal nets:\n", 'red');
	print join('', @ModDecl);
	print "\n\n";
	print join('', @IntNets);
	print "\n";
}

sub print_err{
	my $msg = shift;
	
	print STDERR color('red');
	print STDERR $msg;
	print STDERR color('reset');
	print STDERR "\n";
}

sub print_color{
	no strict 'vars';
	my $msg = shift;
	my $color = shift;
	
	print color($color) if defined($COLORTERM);
	print $msg;
	print color('reset') if defined($COLORTERM);
}

