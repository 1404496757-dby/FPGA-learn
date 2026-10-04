`timescale 1ns/1ps
module tb_interview;
    reg clk=0,rst_n=0;
    always #10 clk=~clk;
    reg sv=0,mr=0;
    reg signed [15:0] error_value=0,kp=256,ki=128,kd=64;
    wire sr,mv,sat;
    wire signed [15:0] u,integral;
    integer model_i=0,previous=0,expected,wide_i,diff,i;
    longint signed product_sum,scaled;
    pid_q8 #(.I_LIMIT(1024)) pid(clk,rst_n,sv,sr,error_value,kp,ki,kd,mv,mr,u,sat,integral);
    task sample(input integer e,p,iv,d);
        reg expected_sat;
        reg signed [15:0] saved;
        begin
            wide_i=model_i+e;
            model_i=wide_i>1024 ? 1024 : (wide_i < -1024 ? -1024 : wide_i);
            diff=e-previous;
            if(diff>32767) diff=32767;
            if(diff < -32768) diff=-32768;
            previous=e;
            product_sum=longint'(e)*p+longint'(model_i)*iv+longint'(diff)*d;
            scaled=product_sum>>>8;
            expected=scaled>32767 ? 32767 : (scaled < -32768 ? -32768 : scaled);
            expected_sat=scaled>32767 || scaled < -32768;
            wait(sr); @(negedge clk); sv=1; error_value=e; kp=p; ki=iv; kd=d;
            @(posedge clk); @(negedge clk); sv=0;
            wait(mv);
            if(u!==expected || sat!==expected_sat || integral!==model_i)
                $fatal(1,"PID e=%0d expected=%0d got=%0d I=%0d",e,expected,u,integral);
            saved=u;
            repeat(5) begin @(negedge clk); if(!mv || u!==saved) $fatal(1,"PID output stall failure"); end
            mr=1; @(negedge clk); mr=0;
        end
    endtask
    reg pid_done=0,pwm_done=0;
    initial begin
        repeat(10) @(negedge clk); rst_n=1;
        sample(10,256,128,64); sample(-8,256,128,64);
        sample(32767,32767,0,0); sample(-32768,32767,0,0);
        for(i=0;i<16;i=i+1) sample(200,256,128,32);
        sample(-32768,-32768,-32768,-32768);
        pid_done=1;
    end
    reg [15:0] duty=0;
    wire ph,pl;
    pwm_deadtime pwm(clk,rst_n,duty,ph,pl);
    integer tick=0,high_fall=-100000,low_fall=-100000,high_rises=0,low_rises=0;
    reg previous_high=0,previous_low=0;
    always @(negedge clk) if(rst_n) begin
        tick=tick+1;
        if(ph && pl) $fatal(1,"PWM shoot-through");
        if(previous_high && !ph) high_fall=tick;
        if(previous_low && !pl) low_fall=tick;
        if(ph && !previous_high) begin
            if(tick-low_fall<50) $fatal(1,"PWM high dead time too short");
            high_rises=high_rises+1;
        end
        if(pl && !previous_low) begin
            if(tick-high_fall<50) $fatal(1,"PWM low dead time too short");
            low_rises=low_rises+1;
        end
        previous_high=ph; previous_low=pl;
    end
    initial begin
        wait(rst_n); repeat(3000) @(posedge clk);
        duty=1250; repeat(12000) @(posedge clk);
        duty=2500; repeat(6000) @(posedge clk);
        if(!ph || pl) $fatal(1,"PWM full duty not settled");
        duty=0; repeat(6000) @(posedge clk);
        if(ph || !pl || high_rises<3 || low_rises<3) $fatal(1,"PWM zero duty/coverage failure");
        pwm_done=1;
    end
    initial begin
        wait(pid_done && pwm_done);
        $display("PASS_INTERVIEW: signed PID/Q8/saturation/integral limit/stalls, complementary PWM/dead-time"); $finish;
    end
    initial begin #1000000; $fatal(1,"Interview tests timeout"); end
endmodule
