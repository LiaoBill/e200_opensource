 /*                                                                      
 Copyright 2017 Silicon Integrated Microelectronics, Inc.                
                                                                         
 Licensed under the Apache License, Version 2.0 (the "License");         
 you may not use this file except in compliance with the License.        
 You may obtain a copy of the License at                                 
                                                                         
     http://www.apache.org/licenses/LICENSE-2.0                          
                                                                         
  Unless required by applicable law or agreed to in writing, software    
 distributed under the License is distributed on an "AS IS" BASIS,       
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and     
 limitations under the License.                                          
 */                                                                      
                                                                         
                                                                         
                                                                         
//=====================================================================
//--        _______   ___
//--       (   ____/ /__/
//--        \ \     __
//--     ____\ \   / /
//--    /_______\ /_/   MICROELECTRONICS
//--
//=====================================================================
// Designer   : Bob Hu
//
// Description:
//  The Regfile module to implement the core's general purpose registers file
//
// ====================================================================
`include "e203_defines.v"

module e203_exu_regfile(
  //读取的第一个源寄存器rs1的序号
  input  [`E203_RFIDX_WIDTH-1:0] read_src1_idx,
  //读取的第二个源寄存器rs2的序号
  input  [`E203_RFIDX_WIDTH-1:0] read_src2_idx,
  //输出读取的第一个源寄存器rs1中的数据
  output [`E203_XLEN-1:0] read_src1_dat,
  //输出读取的第二个源寄存器rs2中的数据
  output [`E203_XLEN-1:0] read_src2_dat,

  //写使能信号
  input  wbck_dest_wen,
  //写回的数据的寄存器的序号
  input  [`E203_RFIDX_WIDTH-1:0] wbck_dest_idx,
  //写回的数据
  input  [`E203_XLEN-1:0] wbck_dest_dat,

  //将x1的值硬连线连出
  output [`E203_XLEN-1:0] x1_r,

  //是否为测试模式
  input  test_mode,
  //时钟信号
  input  clk,
  input  rst_n
  );

  //使用二维数组实现的寄存器文件
  wire [`E203_XLEN-1:0] rf_r [`E203_RFREG_NUM-1:0];
  //每个寄存器的写使能信号
  wire [`E203_RFREG_NUM-1:0] rf_wen;
  
  `ifdef E203_REGFILE_LATCH_BASED //{
  // Use DFF to buffer the write-port
  wire [`E203_XLEN-1:0] wbck_dest_dat_r;

  //sirv_gnrl_dffl(.lden(wbck_dest_wen), .dnxt(wbck_dest_dat), .qout(wbck_dest_dat_r), .clk(clk))
  //              input(加载数据使能信号)   input(加载的数据)      output(保存的数据)     input(时钟信号)
  sirv_gnrl_dffl #(`E203_XLEN) wbck_dat_dffl (wbck_dest_wen, wbck_dest_dat, wbck_dest_dat_r, clk);
  wire [`E203_RFREG_NUM-1:0] clk_rf_ltch;
  `endif//}

  
  genvar i;
  generate //{
  
      for (i=0; i<`E203_RFREG_NUM; i=i+1) begin:regfile//{
  
        if(i==0) begin: rf0
            // x0 cannot be wrote since it is constant-zeros
            //rf_wen[0]恒为0，因为x0中保存的是常数0
            assign rf_wen[i] = 1'b0;
            //DFF: D flip-flop
            //x0设置为E203_XLEN个0，这里不需要dff，节省掉一些硬件资源
            assign rf_r[i] = `E203_XLEN'b0;
          `ifdef E203_REGFILE_LATCH_BASED //{
            //如果使用基于锁存器的寄存器文件则将clk_rf_ltch[0]设置为0
            assign clk_rf_ltch[i] = 1'b0;
          `endif//}
        end
        else begin: rfno0
            //第i个寄存器的写使能信号
            assign rf_wen[i] = wbck_dest_wen & (wbck_dest_idx == i) ;
          `ifdef E203_REGFILE_LATCH_BASED //{
            e203_clkgate u_e203_clkgate(
              .clk_in  (clk  ),
              .test_mode(test_mode),
              .clock_en(rf_wen[i]),
              .clk_out (clk_rf_ltch[i])
            );

            //如果是使用锁存器的配置，则例化锁存器实现通用寄存器
                //from write-enable to clk_rf_ltch to rf_ltch
            sirv_gnrl_ltch #(`E203_XLEN) rf_ltch (clk_rf_ltch[i], wbck_dest_dat_r, rf_r[i]);
          `else//}{
            //
            sirv_gnrl_dffl #(`E203_XLEN) rf_dffl (rf_wen[i], wbck_dest_dat, rf_r[i], clk);
            //sirv_gnrl_dffl(.lden(rf_wen[i]), .dnxt(wbck_dest_dat), .qout(rf_r[i]), .clk(clk))
            //              input(加载数据使能信号)   input(加载的数据)  output(保存的数据)     input(时钟信号)
            //              为1时能够写寄存器         要写入的数据      将寄存器中保存的放到rf_r[i]上
          `endif//}
        end
  
      end//}
  endgenerate//}
  //读取rs1对应的数据
  assign read_src1_dat = rf_r[read_src1_idx];
  //读取rs2对应的数据
  assign read_src2_dat = rf_r[read_src2_idx];
  
 // wire  [`E203_XLEN-1:0] x0  = rf_r[0];
 // wire  [`E203_XLEN-1:0] x1  = rf_r[1];
 // wire  [`E203_XLEN-1:0] x2  = rf_r[2];
 // wire  [`E203_XLEN-1:0] x3  = rf_r[3];
 // wire  [`E203_XLEN-1:0] x4  = rf_r[4];
 // wire  [`E203_XLEN-1:0] x5  = rf_r[5];
 // wire  [`E203_XLEN-1:0] x6  = rf_r[6];
 // wire  [`E203_XLEN-1:0] x7  = rf_r[7];
 // wire  [`E203_XLEN-1:0] x8  = rf_r[8];
 // wire  [`E203_XLEN-1:0] x9  = rf_r[9];
 // wire  [`E203_XLEN-1:0] x10 = rf_r[10];
 // wire  [`E203_XLEN-1:0] x11 = rf_r[11];
 // wire  [`E203_XLEN-1:0] x12 = rf_r[12];
 // wire  [`E203_XLEN-1:0] x13 = rf_r[13];
 // wire  [`E203_XLEN-1:0] x14 = rf_r[14];
 // wire  [`E203_XLEN-1:0] x15 = rf_r[15];
 // `ifdef E203_RFREG_NUM_IS_32 //{ 
 // wire  [`E203_XLEN-1:0] x16 = rf_r[16];
 // wire  [`E203_XLEN-1:0] x17 = rf_r[17];
 // wire  [`E203_XLEN-1:0] x18 = rf_r[18];
 // wire  [`E203_XLEN-1:0] x19 = rf_r[19];
 // wire  [`E203_XLEN-1:0] x20 = rf_r[20];
 // wire  [`E203_XLEN-1:0] x21 = rf_r[21];
 // wire  [`E203_XLEN-1:0] x22 = rf_r[22];
 // wire  [`E203_XLEN-1:0] x23 = rf_r[23];
 // wire  [`E203_XLEN-1:0] x24 = rf_r[24];
 // wire  [`E203_XLEN-1:0] x25 = rf_r[25];
 // wire  [`E203_XLEN-1:0] x26 = rf_r[26];
 // wire  [`E203_XLEN-1:0] x27 = rf_r[27];
 // wire  [`E203_XLEN-1:0] x28 = rf_r[28];
 // wire  [`E203_XLEN-1:0] x29 = rf_r[29];
 // wire  [`E203_XLEN-1:0] x30 = rf_r[30];
 // wire  [`E203_XLEN-1:0] x31 = rf_r[31];
 // `endif//}

  //硬连线将x1的值连出
  assign x1_r = rf_r[1];
      
endmodule

