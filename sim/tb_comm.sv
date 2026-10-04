`timescale 1ns/1ps
module tb_comm;
    reg clk=0,rst_n=0;
    always #10 clk=~clk;
    reg [7:0] rx_data=0;
    reg rx_valid=0;
    wire rx_ready,tx_valid;
    wire [7:0] tx_data;
    reg tx_ready=0;
    wire sclk,mosi,cs;
    wire [31:0] drops,commands;
    integer count=0,cycle=0;
    reg [7:0] reply[0:255];
    reg held_valid=0;
    reg [7:0] held_data;
    comm_service #(.FIFO_DEPTH(8),.TIMEOUT_CYCLES(100)) dut(
        .clk(clk),.rst_n(rst_n),.rx_data(rx_data),.rx_valid(rx_valid),.rx_ready(rx_ready),
        .tx_data(tx_data),.tx_valid(tx_valid),.tx_ready(tx_ready),.spi_sclk(sclk),.spi_mosi(mosi),
        .spi_miso(mosi),.spi_cs_n(cs),.dropped_bytes(drops),.completed_commands(commands));
    always @(posedge clk) if(rst_n) begin
        if(held_valid && (!tx_valid || tx_data!==held_data)) $fatal(1,"Comm reply changed while stalled");
        held_valid=tx_valid && !tx_ready; held_data=tx_data;
        if(tx_valid && tx_ready) begin reply[count]=tx_data; count=count+1; end
    end
    always @(negedge clk) if(rst_n) begin
        cycle=cycle+1; tx_ready=(cycle%17)>=6;
    end
    task byte_in(input [7:0] value);
        begin
            @(negedge clk); rx_valid=1; rx_data=value;
            @(posedge clk); while(!rx_ready) @(posedge clk);
            @(negedge clk); rx_valid=0;
        end
    endtask
    task transact(input [7:0] op,seq,value,expected_status,expected_value,input bad_checksum);
        integer start;
        begin
            start=count;
            byte_in(8'hA5); byte_in(op); byte_in(seq); byte_in(value);
            byte_in((8'hA5^op^seq^value)^(bad_checksum ? 8'h01 : 8'h00));
            wait(count==start+5);
            if(reply[start]!==8'h5A || reply[start+1]!==expected_status || reply[start+2]!==seq ||
               reply[start+3]!==expected_value || reply[start+4]!== (8'h5A^expected_status^seq^expected_value))
                $fatal(1,"Comm packet mismatch opcode=%02x",op);
        end
    endtask
    initial begin
        repeat(10) @(negedge clk); rst_n=1;
        transact(0,10,8'hAA,0,8'hAA,0);
        transact(1,11,8'hC1,1,8'hC1,0);
        transact(8'hFF,12,0,8'hE2,0,0);
        transact(0,13,8'h55,8'hE1,0,1);
        // Incomplete request expires, and following framing recovers.
        byte_in(8'hA5); byte_in(0); repeat(140) @(negedge clk);
        transact(0,14,8'hEF,0,8'hEF,0);
        transact(2,15,0,2,0,0);
        repeat(10) @(negedge clk);
        if(drops!=0 || commands!=6 || !cs) $fatal(1,"Comm counters/CS invalid");
        $display("PASS_COMM: echo/SPI/status/checksum/opcode/timeout, reply backpressure"); $finish;
    end
    initial begin #1000000; $fatal(1,"Comm timeout"); end
endmodule
