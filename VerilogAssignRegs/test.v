module top(

        output b,
        input a
);

        always @(*)
        begin
                b = a;
        end

endmodule
