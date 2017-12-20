#!/usr/bin/perl
#
# Inserts "reg" (register) at appropriate lines in the
# module I/O declaration and internal wires
# when a procedural assignment is used for that net as the output
# Otherwise, the Verilog compiler will complain that the
# assignment statement cannot be used in this context

# Note: written as a hack. Many assumptions made about file layout
# Note: May not understand commented lines or comment blocks at all
# Not guaranteed to work for buses or 2-D arrays

# Sujay Phadke, (C) 2017

use strict;
use warnings;
use File::Slurp;

my $inpfile;
#my $outfile;
my @inpLines;

my %IOHash;
my %NetsHash;

my @ModDecl;
my @IntNets;

if (scalar (@ARGV == 0)){
	die "\nNo input file specified!\n";
	exit 1;
}

my $VERIN = $ARGV[0];

open ($inpfile, "<", $VERIN) or die $!;

# read in entire file
@inpLines = read_file($inpfile);

close $inpfile;

BuildIOHash();

ParseProcedures();

PrintOutput();

exit 0;


# Assume ANSI-C style declaration within Verilog
sub BuildIOHash{
	my $flag;
	my $net;
	my $present;
	
	$flag = 0;
	foreach(@inpLines){
		# Module declaration starts with the keyword "module"
		if (($flag == 0) && (m/module/)){
			$flag = 1;
			next;
		}
		# Module declaration must end with ");"
		# NOTE: Assume that this termination is on it's own line
		elsif (($flag == 1) && (m/\);/)){
			$flag = 2;
			push @ModDecl, ");\n";
		}
		
		# Skip commented lines
		if (m/\s*\/\//){
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

			# Remove last char and trailing comma, if present
			# note: the last line of module declaration will not have the comma
			chop $net;
			$net =~ s/,//;

			$IOHash{$net} = $present;
			
		}
		
		# Outside module
		# Parse internal nets (wire or reg)
		if (($flag == 2) && (m/\s*(reg|wire)\s+(?:\[.*\])?\s*(.*)/)){
			# make sure $1 and $2 are stored in some variables
			# before doing other operations
			$present = ($1 eq "reg") ? 1 : 0;
			$net = $2;
			# Remove last char and trailing semi-colon, if present
			chop $net;
			$net =~ s/;//;
			$NetsHash{$net} = $present;
			push @IntNets, $_;
		}
				
	} # end foreach
	
		
	
}

sub ParseProcedures{
	my $flag;
	my $net;
	
	$flag = 0;
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
		if (m/\s*\/\//){
			next;
		}
		
		# Inside procedure.
		if (($flag == 2) && (m/\s*(.+?)\s*=\s*(.+?);/)){
			$net = $1;
						
			if (exists $NetsHash{$net}){
				if ($NetsHash{$net} != 1){
					print "\nlvalue: $net needs to be declared as an internal reg";
					foreach (@IntNets){
						if (m/wire\s+(?:\[.*\])?\s*$net/){
							s/wire/reg/;
						}
					}
				}
				else{
					print "\nlvalue: $net is correctly declared as a reg internally";
				}
			}
			elsif (exists $IOHash{$net}){
				if ($IOHash{$net} != 1){
					print "\nlvalue: $net needs to be a reg in the module declaration";
					foreach (@ModDecl){
						if (m/output\s+(?:\[.*\])?\s*$net/){
							s/output/output reg/;
						}
					}
				}
				else{
					print "\nlvalue: $net is correctly declared as a reg in the module declaration";
				}
			}
			else{
				print "\nlvalue: $net not declared as an output or internet net!";
				print "\nAssuming it to be an internal net and adding it in. Check size, etc.";
				push @IntNets, "reg $net;\t\t// Check size\n";
				
				# Add the net to the nets hash so that it won't be duplicate if another
				# assign statement is present with the same net
				$NetsHash{$net} = 1;
			}
		}
	} # end foreach
			
}

sub PrintOutput{
	print "\n";
	print "\nCorrected Module declaration and Internal nets:\n";
	print join('', @ModDecl);
	print "\n\n";
	print join('', @IntNets);
	print "\n";
}
