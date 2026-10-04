`timescale 1ns/1ps
module tb_spi_checked;
  reg clk=0, rstn=0;
  always #10 clk=~clk;
  wire [3:0] done;
  initial begin repeat(10) @(negedge clk); rstn=1; end
  genvar mode;
  generate for(mode=0;mode<4;mode=mode+1) begin: modes
    reg txdv=0, finished=0;
    reg [7:0] txbyte=0;
    wire ready,rxdv,mosi,sclk;
    wire [7:0] rxbyte;
    integer sent=0, received=0;
    function [7:0] pattern(input integer index);
      pattern=(index*37+mode*11+8'h31)&255;
    endfunction
    assign done[mode]=finished;
    SPI_Master #(.SPI_MODE(mode),.CLKS_PER_HALF_BIT(4)) dut (
      .i_Rst_L(rstn),.i_Clk(clk),.i_TX_Byte(txbyte),.i_TX_DV(txdv),
      .o_TX_Ready(ready),.o_RX_DV(rxdv),.o_RX_Byte(rxbyte),
      .o_SPI_Clk(sclk),.i_SPI_MISO(mosi),.o_SPI_MOSI(mosi));
    always @(posedge clk) if(rstn && rxdv) begin
      if(received>=16 || rxbyte!==pattern(received))
        $fatal(1,"SPI mode=%0d index=%0d got=%02x expected=%02x",mode,received,rxbyte,pattern(received));
      received=received+1;
    end
    initial begin
      wait(rstn); repeat(3) @(negedge clk);
      for(sent=0;sent<16;sent=sent+1) begin
        wait(ready);
        @(negedge clk); txdv=1; txbyte=pattern(sent);
        @(negedge clk); txdv=0;
        wait(ready);
        repeat(2) @(negedge clk);
      end
      wait(received==16); finished=1;
    end
  end endgenerate
  initial begin
    wait(&done); repeat(10) @(negedge clk);
    $display("PASS_SPI: modes 0/1/2/3, 16 loopback bytes per mode"); $finish;
  end
  initial begin #1000000; $fatal(1,"SPI timeout"); end
endmodule
