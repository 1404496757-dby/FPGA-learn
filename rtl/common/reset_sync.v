// Asynchronous assertion, two-clock synchronous release. One instance per domain.
module reset_sync(input wire clk, input wire arst_n, output wire rst_n);
    (* ASYNC_REG = "TRUE" *) reg [1:0] pipe;
    always @(posedge clk or negedge arst_n)
        if (!arst_n) pipe <= 2'b00;
        else pipe <= {pipe[0], 1'b1};
    assign rst_n = pipe[1];
endmodule
