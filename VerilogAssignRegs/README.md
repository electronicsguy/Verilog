# Verilog Assign Registers

Inserts "reg" (register) at appropriate lines in the module I/O declaration and internal wires
when a procedural assignment is used for that net as the output. Otherwise, the Verilog compiler will complain that the
assignment statement cannot be used in this context.

# Note: written as a hack. Many assumptions made about file layout
# Note: May not understand commented lines or comment blocks at all
# Not guaranteed to work for buses or 2-D arrays
# Will not work with split lines
