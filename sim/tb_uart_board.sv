`timescale 1ns/1ps
module tb_uart_board;
    reg clk=0,rst_n=0,valid=0;
    always #10 clk=~clk;
    reg [7:0] data=0;
    wire ready,pc_tx,board_tx,rv,ov;
    wire [7:0] result;
    wire [1:0] led;
    integer count=0;
    reg [7:0] bytes[0:31];
    comm_acx750_top board(clk,rst_n,pc_tx,board_tx,led);
    uart_tx #(.CLK_FREQ(50000000),.BAUD_RATE(115200),.PARITY("NONE"),.STOP_BITS(1)) pc_sender(
        .rstn(rst_n),.clk(clk),.i_tready(ready),.i_tvalid(valid),.i_tdata(data),
        .i_tkeep(1'b1),.i_tlast(1'b0),.o_uart_tx(pc_tx));
    uart_rx #(.CLK_FREQ(50000000),.BAUD_RATE(115200),.PARITY("NONE"),.FIFO_EA(4)) pc_receiver(
        .rstn(rst_n),.clk(clk),.i_uart_rx(board_tx),.o_tready(1'b1),.o_tvalid(rv),.o_tdata(result),.o_overflow(ov));
    always @(posedge clk) if(rst_n) begin
        if(ov) $fatal(1,"PC receive overflow");
        if(rv) begin bytes[count]=result; count=count+1; end
    end
    task send(input [7:0] value);
        begin
            @(negedge clk); valid=1; data=value;
            @(posedge clk); while(!ready) @(posedge clk);
            @(negedge clk); valid=0;
        end
    endtask
    task request(input [7:0] op,seq,value);
        integer start;
        begin
            start=count;
            send(8'hA5); send(op); send(seq); send(value); send(8'hA5^op^seq^value);
            wait(count==start+5);
            if(bytes[start]!==8'h5A || bytes[start+1]!==op || bytes[start+2]!==seq ||
               bytes[start+3]!==value || bytes[start+4]!== (8'h5A^op^seq^value))
                $fatal(1,"Serial board reply mismatch");
        end
    endtask
    initial begin
        repeat(20) @(negedge clk); rst_n=1;
        repeat(2000) @(negedge clk);
        request(0,1,8'h13); request(1,2,8'hC1);
        repeat(1000) @(negedge clk);
        if(led[1]) $fatal(1,"Board drop indicator set");
        $display("PASS_UART_BOARD: 115200 8N1 serial round-trip through complete communication top"); $finish;
    end
    initial begin #5000000; $fatal(1,"Serial board timeout"); end
endmodule
