// Request: A5 opcode sequence data XOR(all preceding four bytes).
// Reply:   5A status sequence result XOR(all preceding four bytes).
// 00 echo, 01 SPI byte, 02 RX-drop-count low byte. E1 checksum, E2 opcode.
// UART producers cannot be stopped by internal ready: rejected bytes are counted.
module comm_service #(
    parameter FIFO_DEPTH=512, parameter SPI_MODE=0, parameter SPI_HALF_CLKS=5,
    parameter TIMEOUT_CYCLES=5000000
)(
    input wire clk, input wire rst_n,
    input wire [7:0] rx_data, input wire rx_valid, output wire rx_ready,
    output reg [7:0] tx_data, output wire tx_valid, input wire tx_ready,
    output wire spi_sclk, output wire spi_mosi, input wire spi_miso, output wire spi_cs_n,
    output reg [31:0] dropped_bytes, output reg [31:0] completed_commands
);
    wire [7:0] qdata;
    wire qvalid, qready;
    stream_fifo #(.DATA_WIDTH(8),.DEPTH(FIFO_DEPTH)) input_fifo(
        .clk(clk),.rst_n(rst_n),.s_data(rx_data),.s_valid(rx_valid),.s_ready(rx_ready),
        .m_data(qdata),.m_valid(qvalid),.m_ready(qready),.level(),.full(),.empty());
    localparam SYNC=0, COMMAND=1, SEQ=2, DATA=3, CHECK=4, EXECUTE=5,
               SPI_REQ=6, SPI_RESULT=7, REPLY=8;
    reg [3:0] state;
    reg [7:0] opcode, sequence_id, payload, checksum, status, result;
    reg [2:0] reply_index;
    reg [31:0] watchdog;
    assign qready = state<=CHECK;
    wire take = qvalid && qready;
    wire spi_req_ready, spi_result_valid;
    wire [7:0] spi_result_data;
    spi_byte_engine #(.SPI_MODE(SPI_MODE),.CLKS_PER_HALF_BIT(SPI_HALF_CLKS)) spi(
        .clk(clk),.rst_n(rst_n),.s_data(payload),.s_valid(state==SPI_REQ),.s_ready(spi_req_ready),
        .m_data(spi_result_data),.m_valid(spi_result_valid),.m_ready(state==SPI_RESULT),
        .spi_sclk(spi_sclk),.spi_mosi(spi_mosi),.spi_miso(spi_miso),.spi_cs_n(spi_cs_n));
    assign tx_valid = state == REPLY;
    always @* case(reply_index)
        0: tx_data=8'h5A; 1: tx_data=status; 2: tx_data=sequence_id;
        3: tx_data=result; default: tx_data=8'h5A^status^sequence_id^result;
    endcase
    always @(posedge clk) begin
        if(!rst_n) begin
            state<=SYNC; opcode<=0; sequence_id<=0; payload<=0; checksum<=0;
            status<=0; result<=0; reply_index<=0; watchdog<=0;
            dropped_bytes<=0; completed_commands<=0;
        end else begin
            if(rx_valid && !rx_ready) dropped_bytes<=dropped_bytes+1'b1;
            if(state>=COMMAND && state<=CHECK && !take) watchdog<=watchdog+1'b1;
            else watchdog<=0;
            case(state)
                SYNC: if(take && qdata==8'hA5) begin checksum<=8'hA5; state<=COMMAND; end
                COMMAND: if(take) begin opcode<=qdata; checksum<=checksum^qdata; state<=SEQ; end
                SEQ: if(take) begin sequence_id<=qdata; checksum<=checksum^qdata; state<=DATA; end
                DATA: if(take) begin payload<=qdata; checksum<=checksum^qdata; state<=CHECK; end
                CHECK: if(take) begin
                    reply_index<=0;
                    if(qdata!=checksum) begin status<=8'hE1; result<=0; state<=REPLY; end
                    else state<=EXECUTE;
                end
                EXECUTE: case(opcode)
                    0: begin status<=0; result<=payload; state<=REPLY; end
                    1: begin status<=1; state<=SPI_REQ; end
                    2: begin status<=2; result<=dropped_bytes[7:0]; state<=REPLY; end
                    default: begin status<=8'hE2; result<=0; state<=REPLY; end
                endcase
                SPI_REQ: if(spi_req_ready) state<=SPI_RESULT;
                SPI_RESULT: if(spi_result_valid) begin result<=spi_result_data; state<=REPLY; end
                REPLY: if(tx_ready) begin
                    if(reply_index==4) begin state<=SYNC; completed_commands<=completed_commands+1'b1; end
                    else reply_index<=reply_index+1'b1;
                end
                default: state<=SYNC;
            endcase
            // Partial packets expire; next A5 can re-establish framing.
            if(state>=COMMAND && state<=CHECK && !take && watchdog>=TIMEOUT_CYCLES-1) begin
                state<=SYNC; watchdog<=0;
            end
        end
    end
endmodule
