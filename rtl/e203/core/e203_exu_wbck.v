 /*
 Copyright 2018 Nuclei System Technology, Inc.

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
//
// Designer   : Bob Hu
//
// Description:
//  The Write-Back module to arbitrate the write-back request to regfile
//
// ====================================================================

`include "e203_defines.v"

// 最终写回仲裁模块
module e203_exu_wbck(

  //////////////////////////////////////////////////////////////
  // The ALU Write-Back Interface
  // 所有单周期指令的写回 (input来自于ALU 模块)
  // Handshake valid 写回握手请求信号
  input  alu_wbck_i_valid,
  // Handshake ready 写回握手反馈信号
  output alu_wbck_i_ready,
  // 写囚的数据值 write back data
  input  [`E203_XLEN-1:0] alu_wbck_i_wdat,
  // 写田的寄存器索引值, register index
  input  [`E203_RFIDX_WIDTH-1:0] alu_wbck_i_rdidx,
  // If ALU have error, it will not generate the wback_valid to wback module
      // so we dont need the alu_wbck_i_err here

  //////////////////////////////////////////////////////////////
  // The Longp Write-Back Interface
  // 所有长指令部分 (input来自于长指令写回仲裁模块)
  // which is a long part write back interface
  input  longp_wbck_i_valid, // Handshake valid
  output longp_wbck_i_ready, // Handshake ready
  // data to wirte back (write back data)
  input  [`E203_FLEN-1:0] longp_wbck_i_wdat,
  // don't know what flags
  input  [5-1:0] longp_wbck_i_flags,
  // target register index
  input  [`E203_RFIDX_WIDTH-1:0] longp_wbck_i_rdidx,
  // register
  input  longp_wbck_i_rdfpu,

  //////////////////////////////////////////////////////////////
  // The Final arbitrated Write-Back Interface to Regfile
  // write enable
  output  rf_wbck_o_ena,
  // write data going to send
  output  [`E203_XLEN-1:0] rf_wbck_o_wdat,
  // register data index
  output  [`E203_RFIDX_WIDTH-1:0] rf_wbck_o_rdidx,


  // clock
  input  clk,
  // reset 复位信号
  input  rst_n
  );


  // --------- add/modify/delete code ---------
  // wire reg_alu_wbck_i_ready;
  // wire reg_longp_wbck_i_ready;
  // wire reg_rf_wbck_o_ena;
  // wire [`E203_XLEN-1:0] reg_rf_wbck_o_wdat; 
  // wire [`E203_RFIDX_WIDTH-1:0] reg_rf_wbck_o_rdidx;

  // sirv_gnrl_dffl #(1) x_reg_alu_wbck_i_ready (1'b1, reg_alu_wbck_i_ready, alu_wbck_i_ready, clk);
  // sirv_gnrl_dffl #(1) x_reg_longp_wbck_i_ready (1'b1, reg_longp_wbck_i_ready, longp_wbck_i_ready, clk);
  // sirv_gnrl_dffl #(1) x_reg_rf_wbck_o_ena (1'b1, reg_rf_wbck_o_ena, rf_wbck_o_ena, clk);
  // sirv_gnrl_dffl #(`E203_XLEN) x_reg_rf_wbck_o_wdat (1'b1, reg_rf_wbck_o_wdat, rf_wbck_o_wdat, clk);
  // sirv_gnrl_dffl #(`E203_RFIDX_WIDTH) x_reg_rf_wbck_o_rdidx (1'b1, reg_rf_wbck_o_rdidx, rf_wbck_o_rdidx, clk);

  // --------- add/modify/delete code ---------

  // The ALU instruction can write-back only when there is no any
  //  long pipeline instruction writing-back
  //    * Since ALU is the 1 cycle instructions, it have lowest
  //      priority in arbitration
  //如果长指令流水线和ALU同时想要写数据，长指令优先
   // writing back whether ready for alu unit (单指令写回是否可以执行)
  // if a request for long part write back is valid, we need to execute long part write back first
  wire wbck_ready4alu = (~longp_wbck_i_valid);
  //alu_wbck_i_valid为1意味着alu想要写数据
  //当alu想写数据并且长指令模不想写数据的时候才选择alu
    // alu have a data to write back
  wire wbck_sel_alu = alu_wbck_i_valid & wbck_ready4alu;
  // The Long-pipe instruction can always write-back since it have high priority 
  //写回模块总是准备好写回长指令的数据
  // always true
  wire wbck_ready4longp = 1'b1;
  //longp_wbck_i_valid为1意味着长指令模块想要写数据
  // also, check whether have a data to write back
  wire wbck_sel_longp = longp_wbck_i_valid & wbck_ready4longp;



  //////////////////////////////////////////////////////////////
  // The Final arbitrated Write-Back Interface
  // 寄存器文件总是可写回的，恒1个binary bit "1", which is high level electricity
  wire rf_wbck_o_ready = 1'b1; // Regfile is always ready to be write because it just has 1 w-port

  // write back is ready
  wire wbck_i_ready;
  // write back is valid
  wire wbck_i_valid;
  // write data going to write back
  wire [`E203_FLEN-1:0] wbck_i_wdat;
  // don't know what flags * 2 --------------------unkown
  wire [5-1:0] wbck_i_flags;
  // write back target register index
  wire [`E203_RFIDX_WIDTH-1:0] wbck_i_rdidx;
  // register data float point unit or something???? --------------------unkown
  wire wbck_i_rdfpu;


  //返回给alu的状态信息
//   assign alu_wbck_i_ready   = wbck_ready4alu   & wbck_i_ready;
//   assign longp_wbck_i_ready = wbck_ready4longp & wbck_i_ready;


  // --------- add/modify/delete code ---------
  // input alu is valid (which is a request)
  // and output is a ready flag, which used wbck_ready4alu for calculation
  // means if ready(no further long part to write), and current

  assign alu_wbck_i_ready   = wbck_ready4alu   & wbck_i_ready;
  // assign reg_alu_wbck_i_ready   = wbck_ready4alu   & wbck_i_ready;
  // --------- add/modify/delete code ---------
  
  // --------- add/modify/delete code ---------
  assign longp_wbck_i_ready = wbck_ready4longp & wbck_i_ready;
  // assign reg_longp_wbck_i_ready = wbck_ready4longp & wbck_i_ready;
  // --------- add/modify/delete code ---------

  
  assign wbck_i_valid = wbck_sel_alu ? alu_wbck_i_valid : longp_wbck_i_valid;
  `ifdef E203_FLEN_IS_32//{
    //选择写回数据
  assign wbck_i_wdat  = wbck_sel_alu ? alu_wbck_i_wdat  : longp_wbck_i_wdat;
  `else//}{
          //选择写回数据
  assign wbck_i_wdat  = wbck_sel_alu ? {{`E203_FLEN-`E203_XLEN{1'b0}},alu_wbck_i_wdat}  : longp_wbck_i_wdat;
  `endif//}
  //写回标识，alu没有写回标识，长指令的写回标识是由长指令模块传入的
  assign wbck_i_flags = wbck_sel_alu ? 5'b0  : longp_wbck_i_flags;
  //选择写回的寄存器编号
  assign wbck_i_rdidx = wbck_sel_alu ? alu_wbck_i_rdidx : longp_wbck_i_rdidx;
  assign wbck_i_rdfpu = wbck_sel_alu ? 1'b0 : longp_wbck_i_rdfpu;

  // If it have error or non-rdwen it will not be send to this module
  //   instead have been killed at EU level, so it is always need to
  //   write back into regfile at here
  assign wbck_i_ready  = rf_wbck_o_ready;
  wire rf_wbck_o_valid = wbck_i_valid;

  wire wbck_o_ena   = rf_wbck_o_valid & rf_wbck_o_ready;

  // --------- add/modify/delete code ---------
  assign rf_wbck_o_ena   = wbck_o_ena & (~wbck_i_rdfpu);
  // assign reg_rf_wbck_o_ena   = wbck_o_ena & (~wbck_i_rdfpu);
  // --------- add/modify/delete code ---------

  // --------- add/modify/delete code ---------
  assign rf_wbck_o_wdat  = wbck_i_wdat[`E203_XLEN-1:0];
  // assign reg_rf_wbck_o_wdat  = wbck_i_wdat[`E203_XLEN-1:0];
  assign rf_wbck_o_rdidx = wbck_i_rdidx;
  // assign reg_rf_wbck_o_rdidx = wbck_i_rdidx;
  // --------- add/modify/delete code ---------


endmodule


