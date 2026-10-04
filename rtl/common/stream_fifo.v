// Registered ready/valid FIFO with synchronous RAM read, suitable for BRAM.
// DEPTH includes the output register: occupancy = RAM words + output-valid.
// Read prefetch moves RAM data into the output slot; only m_valid&&m_ready
// transfers it to a consumer. RAM contents are not cleared on reset.
module stream_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH = 512,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input wire clk, input wire rst_n,
    input wire [DATA_WIDTH-1:0] s_data, input wire s_valid, output wire s_ready,
    output reg [DATA_WIDTH-1:0] m_data, output reg m_valid, input wire m_ready,
    output wire [ADDR_WIDTH:0] level, output wire full, output wire empty
);
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] wptr, rptr;
    reg [ADDR_WIDTH:0] ram_count;
    reg reset_done;
    wire pop = m_valid && m_ready;
    wire fetch = (ram_count != 0) && (!m_valid || m_ready);
    assign level = ram_count + m_valid;
    assign full = (level == DEPTH);
    assign empty = (level == 0);
    assign s_ready = reset_done && (!full || pop);
    wire push = s_valid && s_ready;
    always @(posedge clk) begin
        if (push) mem[wptr] <= s_data;
        if (fetch) m_data <= mem[rptr];
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            wptr <= 0; rptr <= 0; ram_count <= 0; m_valid <= 0; reset_done <= 0;
        end else begin
            reset_done <= 1;
            if (push) wptr <= wptr + 1'b1;
            if (fetch) rptr <= rptr + 1'b1;
            case ({push, fetch})
                2'b10: ram_count <= ram_count + 1'b1;
                2'b01: ram_count <= ram_count - 1'b1;
                default: ram_count <= ram_count;
            endcase
            if (fetch) m_valid <= 1'b1;
            else if (pop) m_valid <= 1'b0;
        end
    end
    // synthesis translate_off
    initial if (DEPTH < 2 || (1 << ADDR_WIDTH) != DEPTH)
        $fatal(1, "stream_fifo DEPTH must be a power of two >= 2");
    // synthesis translate_on
endmodule
