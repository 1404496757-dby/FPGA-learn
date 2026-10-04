`timescale 1ns/1ps
module tb_common;
    reg clk=0,arst_n=0;
    always #10 clk=~clk;
    reg sv=0,mr=0;
    reg [15:0] sd=0;
    wire sr,mv,full,empty;
    wire [15:0] md;
    wire [3:0] level;
    integer sent=0,received=0,model_count=0,head=0,tail=0;
    reg [15:0] model[0:10000];
    reg stalled=0;
    reg [15:0] held;
    reg saw_full=0,saw_empty=0,saw_both=0, fifo_done=0;
    reg [31:0] random_state=32'hCAFE1234;
    stream_fifo #(.DATA_WIDTH(16),.DEPTH(8)) fifo(clk,arst_n,sd,sv,sr,md,mv,mr,level,full,empty);
    always @(posedge clk) if(arst_n) begin
        if(stalled && (!mv || md!==held)) $fatal(1,"FIFO changed while stalled");
        stalled=mv && !mr; held=md;
        if(level!==model_count) $fatal(1,"FIFO level=%0d model=%0d",level,model_count);
        if(full) saw_full=1;
        if(empty) saw_empty=1;
        if(sv && sr && mv && mr) saw_both=1;
        if(mv && mr) begin
            if(model_count==0 || md!==model[head]) $fatal(1,"FIFO reorder/empty consumption");
            head=head+1; model_count=model_count-1; received=received+1;
        end
        if(sv && sr) begin
            model[tail]=sd; tail=tail+1; model_count=model_count+1; sent=sent+1;
        end
    end
    integer k;
    initial begin
        repeat(8) @(negedge clk); arst_n=1;
        for(k=0;k<3000;k=k+1) begin
            @(negedge clk);
            random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            sv=(sv && !sr) ? 1'b1 : (k<100 ? 1'b1 : random_state[0]);
            sd=sent*37+11;
            mr=k<100 ? 0 : random_state[4];
        end
        @(negedge clk); sv=0; mr=1;
        wait(model_count==0); repeat(4) @(negedge clk);
        if(!saw_full || !saw_empty || !saw_both || sent<100)
            $fatal(1,"Insufficient synchronous FIFO coverage");
        fifo_done=1;
    end
    // Asynchronous FIFO: independent 50MHz and ~38.46MHz clocks.
    reg rdclk=0;
    always #13 rdclk=~rdclk;
    reg av=0,read_en=0;
    reg [7:0] ad=0;
    wire ar,af,ae,rv,wr_reset,rd_reset;
    wire [7:0] aq;
    integer asend=0,arecv=0;
    reg async_done=0,saw_async_full=0,saw_async_empty=0;
    async_fifo #(.ADDR_WIDTH(3)) afifo(arst_n,clk,rdclk,av,ad,ar,af,read_en,aq,rv,ae,wr_reset,rd_reset);
    always @(posedge clk) if(wr_reset) begin
        if(af) saw_async_full=1;
        if(av && ar) asend=asend+1;
    end
    always @(posedge rdclk) if(rd_reset) begin
        if(ae && read_en) saw_async_empty=1;
        if(rv) begin
            if(aq!==((arecv*29+7)&255) || arecv>=asend) $fatal(1,"Async FIFO lost/reordered data");
            arecv=arecv+1;
        end
    end
    initial begin
        wait(wr_reset);
        while(asend<400) begin
            @(negedge clk); av=(asend<400); ad=(asend*29+7)&255;
        end
        @(negedge clk); av=0;
        wait(arecv==400); repeat(20) @(negedge rdclk);
        if(!saw_async_full || !saw_async_empty) $fatal(1,"Insufficient async FIFO full/empty coverage");
        async_done=1;
    end
    initial begin
        wait(rd_reset); read_en=1;
        repeat(4) @(negedge rdclk); read_en=0;
        repeat(100) @(negedge rdclk);
        forever begin @(negedge rdclk); read_en=($time%182)!=0; end
    end
    reg event_valid=0;
    wire event_ready,event_pulse;
    integer events_sent=0,events_seen=0;
    reg event_done=0;
    event_cdc events(arst_n,clk,rdclk,event_valid,event_ready,event_pulse);
    always @(posedge clk) if(arst_n && event_valid && event_ready) events_sent=events_sent+1;
    always @(posedge rdclk) if(arst_n && event_pulse) events_seen=events_seen+1;
    initial begin
        wait(event_ready);
        repeat(40) begin
            @(negedge clk); event_valid=1;
            @(posedge clk); while(!event_ready) @(posedge clk);
            @(negedge clk); event_valid=0;
        end
        wait(events_seen==40); repeat(10) @(negedge rdclk);
        if(events_sent!=40) $fatal(1,"Event handshake mismatch");
        event_done=1;
    end
    initial begin
        wait(fifo_done && async_done && event_done);
        $display("PASS_COMMON: sync FIFO random/full/empty/stalls, async FIFO 400 words, CDC 40 events"); $finish;
    end
    initial begin #1000000; $fatal(1,"Common tests timeout"); end
endmodule
