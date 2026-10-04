// For a single-bit LEVEL. This does not preserve arbitrary short pulses or buses.
module bit_sync(input wire clk, input wire rst_n, input wire async_bit, output wire sync_bit);
    (* ASYNC_REG = "TRUE" *) reg stage1, stage2;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin stage1 <= 1'b0; stage2 <= 1'b0; end
        else begin stage1 <= async_bit; stage2 <= stage1; end
    assign sync_bit = stage2;
endmodule
