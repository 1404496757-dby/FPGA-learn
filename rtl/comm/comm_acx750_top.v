// ACX750 board baseline: SPI uses internal MOSI/MISO loopback (no external sensor).
module comm_acx750_top(
    input wire clk, input wire reset_n, input wire uart_rx, output wire uart_tx,
    output wire [1:0] led
);
    wire rst_n;
    reset_sync reset_domain(clk, reset_n, rst_n);
    (* ASYNC_REG="TRUE" *) reg rx_meta, rx_sync;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) begin rx_meta<=1; rx_sync<=1; end
        else begin rx_meta<=uart_rx; rx_sync<=rx_meta; end
    wire [7:0] raw_byte, tx_byte;
    wire raw_valid, rx_ready, tx_valid, tx_ready, overflow;
    reg [7:0] rx_byte;
    reg rx_valid;
    // Synchronously reset ingress registers isolate async-reset vendor outputs
    // from BRAM enables. No ready signal can stop the physical UART source.
    always @(posedge clk)
        if(!rst_n) begin rx_byte<=0; rx_valid<=0; end
        else begin rx_byte<=raw_byte; rx_valid<=raw_valid; end
    wire spi_mosi, spi_sclk, spi_cs_n;
    wire [31:0] drops, commands;
    uart_rx #(.CLK_FREQ(50000000),.BAUD_RATE(115200),.PARITY("NONE"),.FIFO_EA(0)) receiver(
        .rstn(rst_n),.clk(clk),.i_uart_rx(rx_sync),.o_tready(1'b1),
        .o_tvalid(raw_valid),.o_tdata(raw_byte),.o_overflow(overflow));
    comm_service service(.clk(clk),.rst_n(rst_n),.rx_data(rx_byte),.rx_valid(rx_valid),.rx_ready(rx_ready),
        .tx_data(tx_byte),.tx_valid(tx_valid),.tx_ready(tx_ready),
        .spi_sclk(spi_sclk),.spi_mosi(spi_mosi),.spi_miso(spi_mosi),.spi_cs_n(spi_cs_n),
        .dropped_bytes(drops),.completed_commands(commands));
    uart_tx #(.CLK_FREQ(50000000),.BAUD_RATE(115200),.PARITY("NONE"),.STOP_BITS(1),.FIFO_EA(0)) transmitter(
        .rstn(rst_n),.clk(clk),.i_tready(tx_ready),.i_tvalid(tx_valid),.i_tdata(tx_byte),
        .i_tkeep(1'b1),.i_tlast(1'b0),.o_uart_tx(uart_tx));
    assign led[0]=commands[0];
    assign led[1]=drops!=0;
endmodule
