`timescale 1ns/1ps
module tb_image;
    reg clk=0,rst_n=0,rx_valid=0,tx_ready=0;
    always #20 clk=~clk;
    reg [7:0] rx_data=0;
    wire rx_ready,tx_valid,small_ready,small_valid;
    wire [7:0] tx_data,small_data;
    wire feed_valid=rx_valid && rx_ready && small_ready;
    wire [31:0] good,bad,small_good,small_bad;
    jls_frame_service #(.TIMEOUT_CYCLES(1000)) dut(
        .clk(clk),.rst_n(rst_n),.rx_data(rx_data),.rx_valid(feed_valid),.rx_ready(rx_ready),
        .tx_data(tx_data),.tx_valid(tx_valid),.tx_ready(tx_ready),.busy(),.good_frames(good),.bad_frames(bad));
    jls_frame_service #(.CODE_WORDS(8),.TIMEOUT_CYCLES(1000)) tiny_buffer(
        .clk(clk),.rst_n(rst_n),.rx_data(rx_data),.rx_valid(feed_valid),.rx_ready(small_ready),
        .tx_data(small_data),.tx_valid(small_valid),.tx_ready(tx_ready),.busy(),
        .good_frames(small_good),.bad_frames(small_bad));
    reg [7:0] response[0:65543],small_response[0:65543];
    integer count=0,small_count=0,length=0,small_length=0,cycle=0;
    reg response_done=0,small_done=0,stalled=0,small_stalled=0;
    reg [7:0] held,small_held;
    always @(negedge clk) if(rst_n) begin cycle=cycle+1; tx_ready=(cycle%19)>=7; end
    always @(posedge clk) if(rst_n) begin
        if(stalled && (!tx_valid || tx_data!==held)) $fatal(1,"Image output changed under backpressure");
        stalled=tx_valid && !tx_ready; held=tx_data;
        if(small_stalled && (!small_valid || small_data!==small_held)) $fatal(1,"Small-buffer output stall failure");
        small_stalled=small_valid && !tx_ready; small_held=small_data;
        if(tx_valid && tx_ready) begin
            if(response_done || count>=65544) $fatal(1,"Unexpected image response bytes");
            response[count]=tx_data; count=count+1;
            if(count==6) length=response[4]+256*response[5];
            if(count>=8 && count==length+8) response_done=1;
        end
        if(small_valid && tx_ready) begin
            if(small_done || small_count>=65544) $fatal(1,"Unexpected small response bytes");
            small_response[small_count]=small_data; small_count=small_count+1;
            if(small_count==6) small_length=small_response[4]+256*small_response[5];
            if(small_count>=8 && small_count==small_length+8) small_done=1;
        end
    end
    function [15:0] crc;
        input [15:0] old;
        input [7:0] value;
        integer b;
        reg [15:0] c;
        begin
            c=old^{value,8'h00};
            for(b=0;b<8;b=b+1) c=c[15] ? (c<<1)^16'h1021 : (c<<1);
            crc=c;
        end
    endfunction
    task send(input [7:0] value);
        begin
            @(negedge clk); rx_valid=1; rx_data=value;
            @(posedge clk); while(!(rx_ready && small_ready)) @(posedge clk);
            @(negedge clk); rx_valid=0;
        end
    endtask
    task check_response(input [7:0] seq,big_status,tiny_status);
        reg [15:0] check_crc;
        integer b;
        begin
            wait(response_done && small_done);
            if(response[0]!==8'h4A || response[1]!==8'h53 || response[2]!==seq || response[3]!==big_status)
                $fatal(1,"Image header status=%02x expected=%02x",response[3],big_status);
            check_crc=16'hFFFF;
            for(b=2;b<count-2;b=b+1) check_crc=crc(check_crc,response[b]);
            if({response[count-1],response[count-2]}!==check_crc) $fatal(1,"Image reply CRC mismatch");
            if(big_status!=0 && length!=0) $fatal(1,"Error frame contains payload");
            if(small_response[3]!==tiny_status || small_length!=0) $fatal(1,"Overflow/bad-CRC response mismatch");
            check_crc=16'hFFFF;
            for(b=2;b<small_count-2;b=b+1) check_crc=crc(check_crc,small_response[b]);
            if({small_response[small_count-1],small_response[small_count-2]}!==check_crc)
                $fatal(1,"Small-buffer reply CRC mismatch");
            repeat(5) @(negedge clk);
        end
    endtask
    task prepare_response;
        begin
            @(negedge clk); count=0; small_count=0; response_done=0; small_done=0; length=0; small_length=0;
        end
    endtask
    integer frame,p,raw_fd,jls_fd;
    reg [31:0] prng;
    reg [7:0] pixel;
    reg [15:0] input_check;
    string name;
    initial begin
        repeat(10) @(negedge clk); rst_n=1;
        for(frame=0;frame<5;frame=frame+1) begin
            prepare_response;
            if(frame<4) begin name=$sformatf("image_%0d.raw",frame); raw_fd=$fopen(name,"wb"); end
            input_check=crc(16'hFFFF,frame+10); prng=32'h12345678;
            send(8'h4A); send(8'h4C); send(frame+10);
            for(p=0;p<4096;p=p+1) begin
                case(frame)
                    0: pixel=127;
                    1: pixel=((p%64)*3+(p/64)*5)&255;
                    2: pixel=((p%64)^(p/64))&1 ? 255 : 0;
                    default: begin prng=prng*32'd1664525+32'd1013904223; pixel=prng[31:24]; end
                endcase
                send(pixel); input_check=crc(input_check,pixel);
                if(frame<4) $fwrite(raw_fd,"%c",pixel);
            end
            if(frame<4) $fclose(raw_fd);
            send(input_check[7:0] ^ (frame==4 ? 1 : 0)); send(input_check[15:8]);
            check_response(frame+10,frame==4 ? 8'hE1 : 0,frame==4 ? 8'hE1 : 8'hE3);
            if(frame<4) begin
                name=$sformatf("image_%0d.jls",frame); jls_fd=$fopen(name,"wb");
                for(p=0;p<length;p=p+1) $fwrite(jls_fd,"%c",response[p+6]);
                $fclose(jls_fd); $display("Encoded frame=%0d bytes=%0d",frame,length);
            end
        end
        prepare_response; send(8'h4A); send(8'h4C); send(42);
        check_response(42,8'hF1,8'hF1);
        if(good!=4 || bad!=2 || small_good!=0 || small_bad!=6) $fatal(1,"Image counter mismatch");
        $display("PASS_IMAGE: four buffered frames, output stalls, CRC rejection, overflow, partial-frame timeout");
        $finish;
    end
    initial begin #10000000; $fatal(1,"Image test timeout"); end
endmodule
