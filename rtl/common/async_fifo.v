// Gray-pointer dual-clock FIFO. Read-request interface, NOT ready/valid output.
// rd_en && !rd_empty issues a read; rd_valid accompanies rd_data one edge later.
// Full writes / empty reads are ignored. Both domains share reset; resetting
// only one live domain is unsupported and may invalidate queued data.
module async_fifo #(
    parameter DATA_WIDTH = 8, parameter ADDR_WIDTH = 4
)(
    input wire arst_n, input wire wr_clk, input wire rd_clk,
    input wire wr_valid, input wire [DATA_WIDTH-1:0] wr_data,
    output wire wr_ready, output reg wr_full,
    input wire rd_en, output reg [DATA_WIDTH-1:0] rd_data,
    output reg rd_valid, output reg rd_empty,
    output wire wr_rst_n, output wire rd_rst_n
);
    reset_sync wr_reset(wr_clk, arst_n, wr_rst_n);
    reset_sync rd_reset(rd_clk, arst_n, rd_rst_n);
    localparam DEPTH = 1 << ADDR_WIDTH;
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_WIDTH:0] wbin, rbin, wgray, rgray;
    (* ASYNC_REG = "TRUE" *) reg [ADDR_WIDTH:0] rgray_w1, rgray_w2;
    (* ASYNC_REG = "TRUE" *) reg [ADDR_WIDTH:0] wgray_r1, wgray_r2;
    assign wr_ready = wr_rst_n && !wr_full;
    wire write_fire = wr_valid && wr_ready;
    wire read_fire = rd_rst_n && rd_en && !rd_empty;
    wire [ADDR_WIDTH:0] wnext = wbin + write_fire;
    wire [ADDR_WIDTH:0] rnext = rbin + read_fire;
    wire [ADDR_WIDTH:0] wg_next = (wnext >> 1) ^ wnext;
    wire [ADDR_WIDTH:0] rg_next = (rnext >> 1) ^ rnext;
    wire full_next = wg_next == {~rgray_w2[ADDR_WIDTH:ADDR_WIDTH-1], rgray_w2[ADDR_WIDTH-2:0]};
    wire empty_next = rg_next == wgray_r2;
    always @(posedge wr_clk) if (write_fire) mem[wbin[ADDR_WIDTH-1:0]] <= wr_data;
    always @(posedge rd_clk) if (read_fire) rd_data <= mem[rbin[ADDR_WIDTH-1:0]];
    always @(posedge wr_clk)
        if (!wr_rst_n) begin wbin<=0; wgray<=0; wr_full<=0; rgray_w1<=0; rgray_w2<=0; end
        else begin
            wbin<=wnext; wgray<=wg_next; wr_full<=full_next;
            rgray_w1<=rgray; rgray_w2<=rgray_w1;
        end
    always @(posedge rd_clk)
        if (!rd_rst_n) begin rbin<=0; rgray<=0; rd_empty<=1; rd_valid<=0; wgray_r1<=0; wgray_r2<=0; end
        else begin
            rbin<=rnext; rgray<=rg_next; rd_empty<=empty_next;
            rd_valid<=read_fire; wgray_r1<=wgray; wgray_r2<=wgray_r1;
        end
    // synthesis translate_off
    initial if (ADDR_WIDTH < 2) $fatal(1, "async_fifo ADDR_WIDTH must be >= 2");
    // synthesis translate_on
endmodule
