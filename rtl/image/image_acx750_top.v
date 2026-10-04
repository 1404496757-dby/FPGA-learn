// 50 MHz board input -> Clocking Wizard 25 MHz for the entire image/UART domain.
// The Vivado build script generates clk_wiz_0. No ADC/camera/DDR/SD dependency.
module image_acx750_top(
    input wire clk, input wire reset_n, input wire uart_rx, output wire uart_tx,
    output wire [1:0] led
);
    wire clk25, locked, rst_n;
    clk_wiz_0 clock_generator(.clk_in1(clk),.reset(!reset_n),.clk_out1(clk25),.locked(locked));
    reset_sync reset_domain(clk25, reset_n && locked, rst_n);
    (* ASYNC_REG="TRUE" *) reg rx_meta, rx_sync;
    always @(posedge clk25 or negedge rst_n)
        if(!rst_n) begin rx_meta<=1; rx_sync<=1; end
        else begin rx_meta<=uart_rx; rx_sync<=rx_meta; end
    wire [7:0] raw_byte, queued_byte, tx_byte;
    wire raw_valid, uart_ready, queued_valid, queued_ready, tx_valid, tx_ready, overflow, busy;
    reg [7:0] uart_byte;
    reg uart_valid;
    always @(posedge clk25)
        if(!rst_n) begin uart_byte<=0; uart_valid<=0; end
        else begin uart_byte<=raw_byte; uart_valid<=raw_valid; end
    wire [31:0] good_frames, bad_frames;
    reg drop_sticky;
    always @(posedge clk25 or negedge rst_n)
        if(!rst_n) drop_sticky<=0;
        else if(uart_valid && !uart_ready) drop_sticky<=1;
    uart_rx #(.CLK_FREQ(25000000),.BAUD_RATE(115200),.PARITY("NONE"),.FIFO_EA(0)) receiver(
        .rstn(rst_n),.clk(clk25),.i_uart_rx(rx_sync),.o_tready(1'b1),
        .o_tvalid(raw_valid),.o_tdata(raw_byte),.o_overflow(overflow));
    stream_fifo #(.DEPTH(64)) input_fifo(.clk(clk25),.rst_n(rst_n),
        .s_data(uart_byte),.s_valid(uart_valid),.s_ready(uart_ready),
        .m_data(queued_byte),.m_valid(queued_valid),.m_ready(queued_ready),.level(),.full(),.empty());
    jls_frame_service service(.clk(clk25),.rst_n(rst_n),.rx_data(queued_byte),.rx_valid(queued_valid),
        .rx_ready(queued_ready),.tx_data(tx_byte),.tx_valid(tx_valid),.tx_ready(tx_ready),
        .busy(busy),.good_frames(good_frames),.bad_frames(bad_frames));
    uart_tx #(.CLK_FREQ(25000000),.BAUD_RATE(115200),.PARITY("NONE"),.STOP_BITS(1),.FIFO_EA(0)) transmitter(
        .rstn(rst_n),.clk(clk25),.i_tready(tx_ready),.i_tvalid(tx_valid),.i_tdata(tx_byte),
        .i_tkeep(1'b1),.i_tlast(1'b0),.o_uart_tx(uart_tx));
    assign led[0]=busy;
    assign led[1]=drop_sticky || bad_frames!=0;
endmodule
