// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the “License”); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

`define REG_CMD        8'b00000000 //BASEADDR+0x00 
`define REG_CFG        8'b00000001 //BASEADDR+0x04
`define REG_CFG2       8'b00000010 //BASEADDR+0x08        

module apb_efuse_if
#(
   parameter APB_ADDR_WIDTH = 12
)
(
   // From SOC
   input  logic                       PCLK,
   input  logic                       PRESETN,

   input  logic                       test_mode_i,

   input  logic [APB_ADDR_WIDTH-1:0]  PADDR,
   input  logic [31:0]                PWDATA,
   input  logic                       PWRITE,
   input  logic                       PSEL,
   input  logic                       PENABLE,
   output logic [31:0]                PRDATA,
   output logic                       PREADY,
   output logic                       PSLVERR    
);

   logic            s_efuse_prog_en_n;
   logic            s_efuse_load;
   logic            s_efuse_read;
   logic            s_efuse_strobe;  
   logic            s_efuse_cs_n;
   logic [11:0]     s_efuse_addr;
   logic [31:0]     s_efuse_rdata;
   logic [1:0]      s_efuse_r_margin;

   logic      [9:0] r_cnt_target_short;
   logic      [9:0] r_cnt_target_medium;
   logic      [9:0] r_cnt_target_long;

   enum logic [4:0] { S_IDLE, S_GO_READ_MODE, S_GO_PROG_MODE, S_READ_MODE, S_READ_ADD, S_READ_STROBE, S_READ_SAMPLE, S_PROG_MODE, S_PROG_ADD, S_PROG_STROBE, S_PROG_HOLD  } CS, NS;
   enum logic [1:0] { S_CNT_IDLE, S_CNT_RUNNING} r_cnt_state_CS, s_cnt_state_NS;

   logic            s_cnt_done;
   logic            s_cnt_start;
   logic            s_cnt_update;
   logic            s_cnt_clr;
   logic      [9:0] s_cnt_target; 
   logic      [9:0] r_cnt_target; 
   logic      [9:0] r_cnt; 
   logic      [9:0] s_cnt_next; 
   logic      [1:0] r_dest;

   logic [7:0] s_apb_addr;

   logic s_cmd_start_read;
   logic s_cmd_start_write;
   logic s_cmd_idle;
   logic s_cmd_rw;
   logic s_cmd_cfg;

   logic [1:0] r_margin;




   // Cnt start from main FSM
   // cnt update and cnt done from thins FSM
   always_ff @(posedge PCLK, negedge PRESETN)
   begin
      if(~PRESETN) 
      begin
         r_cnt_state_CS  <= S_CNT_IDLE;
         r_cnt           <= 'h0;
         r_cnt_target    <= 'h0;
      end
      else
      begin
         if (s_cnt_start)
            r_cnt_target <= s_cnt_target;

         if (s_cnt_start || s_cnt_done)
            r_cnt_state_CS <= s_cnt_state_NS  ;

         if (s_cnt_update)
            r_cnt <= s_cnt_next;
      end
   end



   always_comb
   begin
      s_cnt_update     = 1'b0;
      s_cnt_state_NS   = r_cnt_state_CS;
      s_cnt_done       = 1'b0;
      s_cnt_next       = r_cnt;

      case (r_cnt_state_CS)
         S_CNT_IDLE:
         begin
            if(s_cnt_start)
               s_cnt_state_NS = S_CNT_RUNNING;
         end

         S_CNT_RUNNING:
         begin
            s_cnt_update = 1'b1;

            if (r_cnt_target == r_cnt)
            begin
               s_cnt_next =  'h0;
               s_cnt_done = 1'b1;
               if (~s_cnt_start)
                  s_cnt_state_NS  = S_CNT_IDLE;
            end
            else
            begin
               s_cnt_next = r_cnt + 1;
            end
         end
      endcase // r_cnt_state_CS
   end





   assign s_efuse_addr = s_efuse_read ? {5'h0,PADDR[8:2]} : {PWDATA[4:0],PADDR[8:2]}; 
   



   always_ff @(posedge PCLK, negedge PRESETN)
   begin
      if(~PRESETN) 
         CS <= S_IDLE;
      else
         CS <= NS;
   end





   always_comb
   begin
     
     s_efuse_cs_n            = 1'b1;
     s_efuse_prog_en_n       = 1'b1;
     s_efuse_load            = 1'b0;
     s_efuse_strobe          = 1'b0;  

     
     s_efuse_read            = 1'b1;
     s_cnt_start             = 1'b0;
     s_cnt_target            = 10'h0;
     NS                      = CS;
     PREADY                  = 1'b0;



     case(CS)


       S_IDLE:
       begin
         if(s_cmd_start_read)
         begin
           NS           = S_GO_READ_MODE;
           s_cnt_start  = 1'b1;
           s_cnt_target = r_cnt_target_short;
         end
         else  if (s_cmd_start_write) 
               begin
                 NS           = S_GO_PROG_MODE;
                 s_cnt_start  = 1'b1;
                 s_cnt_target = r_cnt_target_medium;
               end
               else  if (s_cmd_cfg)
                     begin
                       PREADY = 1'b1;
                     end
       end //~ S_IDLE


       S_GO_READ_MODE:
       begin
         s_efuse_cs_n       = 1'b0;
         s_efuse_load       = 1'b1;
         s_efuse_prog_en_n  = 1'b1;

         if (s_cnt_done)
         begin
           PREADY       = 1'b1;
           NS           = S_READ_MODE;
           s_cnt_start  = 1'b1;
           s_cnt_target = r_cnt_target_short;
         end
       end


       S_GO_PROG_MODE:
       begin
         s_efuse_cs_n       = 1'b0;
         s_efuse_load       = 1'b0;
         s_efuse_prog_en_n  = 1'b0;

         if (s_cnt_done)
         begin
           NS   = S_PROG_MODE;
           PREADY       = 1'b1;
           s_cnt_start  = 1'b1;
           s_cnt_target = r_cnt_target_short;
         end
       end



       S_READ_MODE:
       begin
         s_efuse_cs_n       = 1'b0;
         s_efuse_load       = 1'b1;
         s_efuse_prog_en_n  = 1'b1;

         if (s_cmd_rw)
         begin
           NS   = S_READ_ADD;
           s_cnt_start  = 1'b1;
           s_cnt_target = r_cnt_target_short;
         end
         else  if (s_cmd_idle)
               begin
                 NS        = S_IDLE;
                 PREADY    = 1'b1;
                 // s_cnt_start  = 1'b1;
                 // s_cnt_target = r_cnt_target_short;
               end
       end


       S_PROG_MODE:
       begin
         s_efuse_cs_n       = 1'b0;
         s_efuse_load       = 1'b0;
         s_efuse_prog_en_n  = 1'b0;

         if (s_cmd_rw)
         begin
           NS   = S_PROG_ADD;
           s_cnt_start  = 1'b1;
           s_cnt_target = r_cnt_target_short;
         end
         else  if (s_cmd_idle)
               begin
                 NS   = S_IDLE;
                 PREADY = 1'b1;
                 // s_cnt_start  = 1'b1;
                 // s_cnt_target = r_cnt_target_short;
               end
       end



       S_PROG_ADD:
       begin
         s_efuse_read       = 1'b0;
         s_efuse_cs_n       = 1'b0;
         s_efuse_load       = 1'b0;
         s_efuse_prog_en_n  = 1'b0;

         if (s_cnt_done)
         begin
           NS   = S_PROG_STROBE;
           s_cnt_start  = 1'b1;
           s_cnt_target = r_cnt_target_long;
         end
       end

       S_PROG_STROBE:
       begin
         s_efuse_read       = 1'b0;
         s_efuse_cs_n       = 1'b0;
         s_efuse_load       = 1'b0;
         s_efuse_prog_en_n  = 1'b0;
         s_efuse_strobe     = 1'b1;

         if (s_cnt_done)
         begin
           NS   = S_PROG_HOLD;
           s_cnt_start  = 1'b1;
           s_cnt_target = r_cnt_target_medium;
         end
       end


       S_PROG_HOLD:
       begin
         s_efuse_read            = 1'b0;
         s_efuse_cs_n            = 1'b0;
         s_efuse_load            = 1'b0;
         s_efuse_prog_en_n       = 1'b0;
         s_efuse_strobe          = 1'b0;

         if (s_cnt_done)
         begin
           NS   = S_PROG_MODE;
           s_cnt_start  = 1'b1;
           s_cnt_target = r_cnt_target_medium;
           PREADY       = 1'b1;
         end

       end
+


       // Wait for T_ADDR setup vs Strobe
       S_READ_ADD:
       begin
         s_efuse_cs_n       = 1'b0;
         s_efuse_load       = 1'b1;
         s_efuse_prog_en_n  = 1'b1;

         if (s_cnt_done) // counter == medium range
         begin
           NS   = S_READ_STROBE;
           s_cnt_start  = 1'b1;
           s_cnt_target = r_cnt_target_short;
         end
       end

       S_READ_STROBE:
       begin
         s_efuse_cs_n       = 1'b0;
         s_efuse_load       = 1'b1;
         s_efuse_strobe     = 1'b1;
         if (s_cnt_done)
         begin
           NS   = S_READ_SAMPLE;
           s_cnt_start  = 1'b1;
           s_cnt_target = r_cnt_target_short;
         end
       end


       S_READ_SAMPLE:
       begin
      
         s_efuse_cs_n       = 1'b0;
         s_efuse_load       = 1'b1;
         s_efuse_strobe     = 1'b0;

         if (s_cnt_done)
         begin
           NS   = S_READ_MODE;
           s_cnt_start  = 1'b1;
           s_cnt_target = r_cnt_target_short;
           PREADY       = 1'b1;
         end
       end

     endcase // state
   end


   assign s_apb_addr = PADDR[9:2];















   // Control SIGNALS for the main FSM

   always_comb 
   begin
      s_cmd_start_read  = 1'b0;
      s_cmd_start_write = 1'b0;
      s_cmd_idle        = 1'b0;
      s_cmd_rw          = 1'b0;
      s_cmd_cfg         = 1'b0;


      if (PSEL && PENABLE && s_apb_addr[7])
      begin
         s_cmd_rw = 1'b1;
      end
      else  if (PSEL && PENABLE && PWRITE)
            begin
               if (s_apb_addr == `REG_CMD)
               begin
                  if (PWDATA[0])
                  begin
                     s_cmd_start_read = 1'b1;
                  end
                  else  
                  begin
                        if (PWDATA[1])
                        begin
                           s_cmd_start_write = 1'b1;
                        end
                        else if (PWDATA[2])
                             begin
                                s_cmd_idle = 1'b1;
                             end
                  end
               end
               else
               begin
                  s_cmd_cfg = 1'b1;
               end
            end
   end





   // Update Counters
   always_ff @(posedge PCLK, negedge PRESETN)
   begin
         if(~PRESETN) 
         begin
               r_cnt_target_short  <= 10'd5;
               r_cnt_target_medium <= 10'd50; 
               r_cnt_target_long   <= 10'd500; 
               r_margin            <= 2'b00;
               r_dest              <= 2'b00;
         end
         else
         begin
              if (PSEL && PENABLE && PWRITE)
              begin
                    case (s_apb_addr)
                    `REG_CFG:
                    begin
                      r_cnt_target_short  <= PWDATA[ 9: 0];
                      r_cnt_target_medium <= PWDATA[19:10]; 
                      r_cnt_target_long   <= PWDATA[29:20];
                      r_margin            <= PWDATA[31:30];
                    end
                    
                    `REG_CFG2:
                    begin
                      r_dest <= PWDATA[1:0];
                    end

                    endcase // s_apb_addr

              end
         end
   end

   always_comb
   begin
      PRDATA = '0;
      // normal registers
      case (s_apb_addr)
         `REG_CMD:
            PRDATA = '0;
         `REG_CFG:
            PRDATA = {2'h0,r_cnt_target_long,r_cnt_target_medium,r_cnt_target_short};
          `REG_CFG2:
            PRDATA = {30'h0000_0000,r_dest};
         default:
            PRDATA = s_efuse_rdata;
      endcase // s_apb_addr
  end

  assign PSLVERR    = 1'b0;

  assign s_efuse_r_margin = r_margin;


  /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  // ███████╗███████╗██╗   ██╗███████╗███████╗        ██╗    ██╗██████╗  █████╗ ██████╗ ██████╗ ███████╗██████╗  //
  // ██╔════╝██╔════╝██║   ██║██╔════╝██╔════╝        ██║    ██║██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔════╝██╔══██╗ //
  // █████╗  █████╗  ██║   ██║███████╗█████╗          ██║ █╗ ██║██████╔╝███████║██████╔╝██████╔╝█████╗  ██████╔╝ //
  // ██╔══╝  ██╔══╝  ██║   ██║╚════██║██╔══╝          ██║███╗██║██╔══██╗██╔══██║██╔═══╝ ██╔═══╝ ██╔══╝  ██╔══██╗ //
  // ███████╗██║     ╚██████╔╝███████║███████╗███████╗╚███╔███╔╝██║  ██║██║  ██║██║     ██║     ███████╗██║  ██║ //
  // ╚══════╝╚═╝      ╚═════╝ ╚══════╝╚══════╝╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝     ╚══════╝╚═╝  ╚═╝ //
  /////////////////////////////////////////////////////////////////////////////////////////////////////////////////


   efuse_wrapper i_efuse
   (
      .clk_i         ( PCLK              ),
      .rst_n_i       ( PRESETN           ),
      .dest_i        ( r_dest            ),
      .test_mode_i   ( test_mode_i       ),

      .prog_en_n_i   ( s_efuse_prog_en_n ),
      .load_i        ( s_efuse_load      ),
      .strobe_i      ( s_efuse_strobe    ),  
      .csn_i         ( s_efuse_cs_n      ),
      .read_margin_i ( s_efuse_r_margin  ),

      .addr_i        ( s_efuse_addr      ),
      .rdata_o       ( s_efuse_rdata     )
   );


endmodule