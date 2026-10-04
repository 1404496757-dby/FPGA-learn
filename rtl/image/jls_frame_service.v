// Fixed-size grayscale frame transaction (default 64x64), whole-frame buffering.
// Request: 4A 4C seq pixels... CRC16-low CRC16-high; CRC covers seq+pixels.
// Reply:   4A 53 seq status len-low len-high JLS... CRC16-low CRC16-high.
// Reply CRC covers seq/status/length/JLS; CRC16-CCITT-FALSE, init FFFF.
// 00 success, E1 request CRC, E3 code buffer overflow, F1 RX timeout.
// Encoder has no output-ready: every output word is captured or flagged lost.
module jls_frame_service #(
    parameter IMAGE_W=64, parameter IMAGE_H=64, parameter CODE_WORDS=16384,
    parameter TIMEOUT_CYCLES=12500000
)(
    input wire clk, input wire rst_n,
    input wire [7:0] rx_data, input wire rx_valid, output wire rx_ready,
    output reg [7:0] tx_data, output wire tx_valid, input wire tx_ready,
    output wire busy, output reg [31:0] good_frames, output reg [31:0] bad_frames
);
    localparam PIXELS=IMAGE_W*IMAGE_H, PA=$clog2(PIXELS), CA=$clog2(CODE_WORDS);
    localparam [13:0] WIDTH_MINUS_ONE=IMAGE_W-1, HEIGHT_MINUS_ONE=IMAGE_H-1;
    localparam SYNC1=0,SYNC2=1,SEQ=2,INPUT_PIXELS=3,INPUT_CRC_LO=4,INPUT_CRC_HI=5,
               INIT=6,READ_PIXEL=7,FEED_PIXEL=8,DRAIN=9,HEADER=10,READ_CODE=11,
               SEND_CODE=12,SEND_CRC_LO=13,SEND_CRC_HI=14;
    reg [3:0] state;
    (* ram_style="block" *) reg [7:0] pixel_mem[0:PIXELS-1];
    (* ram_style="block" *) reg [15:0] code_mem[0:CODE_WORDS-1];
    reg [PA:0] input_index, feed_index;
    reg [CA:0] encoded_words;
    reg [CA-1:0] send_word;
    reg [7:0] pixel_read, sequence_id, status, request_crc_low;
    reg [15:0] code_read, response_length, input_crc, output_crc;
    reg [8:0] init_count;
    reg [2:0] header_index;
    reg high_byte, capture_overflow;
    reg [31:0] watchdog;
    function [15:0] crc_step;
        input [15:0] current_crc;
        input [7:0] byte_data;
        integer bit_index;
        reg [15:0] value;
        begin
            value=current_crc^{byte_data,8'h00};
            for(bit_index=0;bit_index<8;bit_index=bit_index+1)
                value=value[15] ? (value<<1)^16'h1021 : value<<1;
            crc_step=value;
        end
    endfunction
    assign rx_ready=state<=INPUT_CRC_HI;
    assign busy=state>=INIT;
    wire take=rx_valid && rx_ready;
    wire encoding_active=state>=INIT && state<=DRAIN;
    wire code_valid,code_last;
    wire [15:0] code_data;
    // The vendor core has asynchronous reset branches. Drive them from a
    // clocked local reset so synthesis cannot put the external asynchronous
    // reset directly on a merged BRAM output register's reset pin.
    reg core_rst_n;
    always @(posedge clk) core_rst_n<=rst_n;
    jls_encoder #(.NEAR(0)) encoder(
        .rstn(core_rst_n),.clk(clk),.i_sof(state==INIT),.i_w(WIDTH_MINUS_ONE),.i_h(HEIGHT_MINUS_ONE),
        .i_e(state==FEED_PIXEL),.i_x(pixel_read),.o_e(code_valid),.o_last(code_last),.o_data(code_data));
    // Synchronous read/write ports: no bulk reset of either RAM array.
    always @(posedge clk) begin
        if(take && state==INPUT_PIXELS) pixel_mem[input_index[PA-1:0]]<=rx_data;
        pixel_read<=pixel_mem[feed_index[PA-1:0]];
        if(encoding_active && code_valid && encoded_words<CODE_WORDS)
            code_mem[encoded_words[CA-1:0]]<=code_data;
        code_read<=code_mem[send_word];
    end
    assign tx_valid=rst_n && (state==HEADER || state==SEND_CODE || state==SEND_CRC_LO || state==SEND_CRC_HI);
    always @* begin
        tx_data=0;
        case(state)
            HEADER: case(header_index)
                0: tx_data=8'h4A; 1: tx_data=8'h53; 2: tx_data=sequence_id;
                3: tx_data=status; 4: tx_data=response_length[7:0];
                default: tx_data=response_length[15:8];
            endcase
            SEND_CODE: tx_data=high_byte ? code_read[15:8] : code_read[7:0];
            SEND_CRC_LO: tx_data=output_crc[7:0];
            SEND_CRC_HI: tx_data=output_crc[15:8];
            default: tx_data=0;
        endcase
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            state<=SYNC1; input_index<=0; feed_index<=0; encoded_words<=0; send_word<=0;
            sequence_id<=0; status<=0; request_crc_low<=0; response_length<=0;
            input_crc<=16'hFFFF; output_crc<=16'hFFFF; init_count<=0; header_index<=0;
            high_byte<=0; capture_overflow<=0; watchdog<=0; good_frames<=0; bad_frames<=0;
        end else begin
            if(state>=SYNC2 && state<=INPUT_CRC_HI && !take) watchdog<=watchdog+1'b1;
            else watchdog<=0;
            if(encoding_active && code_valid) begin
                if(encoded_words<CODE_WORDS) encoded_words<=encoded_words+1'b1;
                else capture_overflow<=1;
            end
            case(state)
                SYNC1: if(take && rx_data==8'h4A) state<=SYNC2;
                SYNC2: if(take) begin
                    if(rx_data==8'h4C) state<=SEQ;
                    else if(rx_data!=8'h4A) state<=SYNC1;
                end
                SEQ: if(take) begin
                    sequence_id<=rx_data; input_crc<=crc_step(16'hFFFF,rx_data);
                    input_index<=0; state<=INPUT_PIXELS;
                end
                INPUT_PIXELS: if(take) begin
                    input_crc<=crc_step(input_crc,rx_data);
                    if(input_index==PIXELS-1) state<=INPUT_CRC_LO;
                    else input_index<=input_index+1'b1;
                end
                INPUT_CRC_LO: if(take) begin request_crc_low<=rx_data; state<=INPUT_CRC_HI; end
                INPUT_CRC_HI: if(take) begin
                    output_crc<=16'hFFFF; header_index<=0; response_length<=0;
                    if({rx_data,request_crc_low}!=input_crc) begin
                        status<=8'hE1; bad_frames<=bad_frames+1'b1; state<=HEADER;
                    end else begin
                        encoded_words<=0; capture_overflow<=0; feed_index<=0; init_count<=0;
                        status<=0; state<=INIT;
                    end
                end
                INIT: if(init_count==367) state<=READ_PIXEL; else init_count<=init_count+1'b1;
                READ_PIXEL: state<=FEED_PIXEL;
                FEED_PIXEL: if(feed_index==PIXELS-1) state<=DRAIN;
                    else begin feed_index<=feed_index+1'b1; state<=READ_PIXEL; end
                DRAIN: state<=DRAIN;
                HEADER: if(tx_ready) begin
                    if(header_index>=2) output_crc<=crc_step(output_crc,tx_data);
                    if(header_index==5) begin
                        if(response_length==0) state<=SEND_CRC_LO;
                        else begin send_word<=0; high_byte<=0; state<=READ_CODE; end
                    end else header_index<=header_index+1'b1;
                end
                READ_CODE: state<=SEND_CODE;
                SEND_CODE: if(tx_ready) begin
                    output_crc<=crc_step(output_crc,tx_data);
                    if(!high_byte) high_byte<=1;
                    else begin
                        high_byte<=0;
                        if(({1'b0,send_word}+1'b1)==encoded_words) state<=SEND_CRC_LO;
                        else begin send_word<=send_word+1'b1; state<=READ_CODE; end
                    end
                end
                SEND_CRC_LO: if(tx_ready) state<=SEND_CRC_HI;
                SEND_CRC_HI: if(tx_ready) state<=SYNC1;
                default: state<=SYNC1;
            endcase
            if(encoding_active && code_valid && code_last) begin
                header_index<=0; output_crc<=16'hFFFF; state<=HEADER;
                if(capture_overflow || encoded_words>=CODE_WORDS) begin
                    status<=8'hE3; response_length<=0; bad_frames<=bad_frames+1'b1;
                end else begin
                    status<=0; response_length<=(encoded_words+1'b1)<<1;
                    good_frames<=good_frames+1'b1;
                end
            end
            if(state>=SYNC2 && state<=INPUT_CRC_HI && !take && watchdog>=TIMEOUT_CYCLES-1) begin
                state<=HEADER; status<=8'hF1; response_length<=0; output_crc<=16'hFFFF;
                header_index<=0; watchdog<=0; bad_frames<=bad_frames+1'b1;
            end
        end
    end
    // synthesis translate_off
    initial begin
        if(IMAGE_W<5 || IMAGE_W>16384 || IMAGE_H<1 || IMAGE_H>16384 || PIXELS<2 || (1<<PA)!=PIXELS)
            $fatal(1,"Image pixels must be a power of two, width >= 5, height >= 1");
        if(CODE_WORDS<2 || CODE_WORDS>16384 || (1<<CA)!=CODE_WORDS)
            $fatal(1,"CODE_WORDS must be power of two in 2..16384");
    end
    // synthesis translate_on
endmodule
