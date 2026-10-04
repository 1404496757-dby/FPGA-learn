// New adapter around nandland SPI_Master: one byte per CS assertion.
// Result is retained until m_ready, instead of forwarding a one-cycle RX pulse.
module spi_byte_engine #(
    parameter SPI_MODE = 0, parameter CLKS_PER_HALF_BIT = 5
)(
    input wire clk, input wire rst_n,
    input wire [7:0] s_data, input wire s_valid, output wire s_ready,
    output reg [7:0] m_data, output wire m_valid, input wire m_ready,
    output wire spi_sclk, output wire spi_mosi, input wire spi_miso,
    output wire spi_cs_n
);
    localparam IDLE=0, SETUP=1, LAUNCH=2, WAIT_RX=3, HOLD_CS=4, RESULT=5;
    reg [2:0] state;
    reg [7:0] tx_byte;
    reg have_rx;
    reg [2:0] delay_count;
    wire master_ready, rx_dv;
    wire [7:0] rx_byte;
    assign s_ready = rst_n && state == IDLE;
    assign m_valid = state == RESULT;
    assign spi_cs_n = state == IDLE || state == RESULT;
    SPI_Master #(.SPI_MODE(SPI_MODE), .CLKS_PER_HALF_BIT(CLKS_PER_HALF_BIT)) core(
        .i_Rst_L(rst_n), .i_Clk(clk), .i_TX_Byte(tx_byte), .i_TX_DV(state==LAUNCH),
        .o_TX_Ready(master_ready), .o_RX_DV(rx_dv), .o_RX_Byte(rx_byte),
        .o_SPI_Clk(spi_sclk), .i_SPI_MISO(spi_miso), .o_SPI_MOSI(spi_mosi));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin state<=IDLE; tx_byte<=0; have_rx<=0; m_data<=0; delay_count<=0; end
        else case(state)
            IDLE: if(s_valid) begin tx_byte<=s_data; have_rx<=0; delay_count<=2; state<=SETUP; end
            SETUP: if(delay_count==0) state<=LAUNCH; else delay_count<=delay_count-1'b1;
            LAUNCH: state<=WAIT_RX;
            WAIT_RX: begin
                if(rx_dv) begin m_data<=rx_byte; have_rx<=1; end
                if(have_rx && master_ready) begin delay_count<=2; state<=HOLD_CS; end
            end
            HOLD_CS: if(delay_count==0) state<=RESULT; else delay_count<=delay_count-1'b1;
            RESULT: if(m_ready) state<=IDLE;
            default: state<=IDLE;
        endcase
    end
endmodule
