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
//  The OITF (Oustanding Instructions Track FIFO) to hold all the non-ALU long
//  pipeline instruction's status and information
//
// ====================================================================
`include "e203_defines.v"

module e203_exu_oitf (
  output dis_ready,

  //派遣一个长指令的便能信号，该信号将用于分配一个 OITF 表项
  input  dis_ena,
  //写回一个长指令的使能信号，该信号将用于移除一个。ITF 表项
  input  ret_ena,

  // 输出的队尾 dis_ptr 和 输出的ret_ptr （ITAG） 标志
  output [`E203_ITAG_WIDTH-1:0] dis_ptr,
  output [`E203_ITAG_WIDTH-1:0] ret_ptr,

  output [`E203_RFIDX_WIDTH-1:0] ret_rdidx,
  output ret_rdwen,
  output ret_rdfpu,
  output [`E203_PC_SIZE-1:0] ret_pc,

  //以下为派遣的长指令相关信息，有的会被存储于OITF的表项中，有的会用于进行 RAW 和 WAW 判断
  //当前派遣指令是否需要读取第一个源操作数寄存器
  input  disp_i_rs1en,
  //当前派遣指令是否需要读取第二个源操作数寄存器
  input  disp_i_rs2en,
  //当前派遣指令是否需要读取第三个源操作数寄存器，注意：只有浮点指令才会使用第三个源操作数
  input  disp_i_rs3en,
  //当前派遣指令是否需要写回结果寄存器
  input  disp_i_rdwen,
  //当前派遣指令第一个源操作数是否是要读取浮点通用寄存器组
  input  disp_i_rs1fpu,
  //当前派遣指令第二个源操作数是否是要读取浮点通用寄存器组
  input  disp_i_rs2fpu,
  //当前派遣指令第三个源操作数是否是要读取浮点通用寄存器组
  input  disp_i_rs3fpu,
  //当前派遣指令的结果寄存器的索引
  input  disp_i_rdfpu,
  //各个读取或写入数据的寄存器的索引
  input  [`E203_RFIDX_WIDTH-1:0] disp_i_rs1idx,
  input  [`E203_RFIDX_WIDTH-1:0] disp_i_rs2idx,
  input  [`E203_RFIDX_WIDTH-1:0] disp_i_rs3idx,
  input  [`E203_RFIDX_WIDTH-1:0] disp_i_rdidx,
  //当前派遣指令的PC
  input  [`E203_PC_SIZE    -1:0] disp_i_pc,

  //派遣指令源操作数一和 OITF任一表项中的结果寄存器相同
  output oitfrd_match_disprs1,
  //派遣指令源操作数二和 OITF任一表项中的结果寄存器相同
  output oitfrd_match_disprs2,
  //派遣指令源操作数三和 OITF任一表项中的结果寄存器相同
  output oitfrd_match_disprs3,
  //派遣指令结果寄存器和 OITF 任一表项中的结果寄存器相同
  output oitfrd_match_disprd,

  output oitf_empty,
  input  clk,
  input  rst_n
);

  wire [`E203_OITF_DEPTH-1:0] vld_set;
  wire [`E203_OITF_DEPTH-1:0] vld_clr;
  wire [`E203_OITF_DEPTH-1:0] vld_ena;
  wire [`E203_OITF_DEPTH-1:0] vld_nxt;
  //各表项中是否存放了有效指令的指示信号
  wire [`E203_OITF_DEPTH-1:0] vld_r;
  //各表项中指令是否写回结果寄存器
  wire [`E203_OITF_DEPTH-1:0] rdwen_r;
  //各表项中指令写回的结果寄存器是否属于浮点
  wire [`E203_OITF_DEPTH-1:0] rdfpu_r;
  //各表项中指令的结果寄存器索引
  wire [`E203_RFIDX_WIDTH-1:0] rdidx_r[`E203_OITF_DEPTH-1:0];
  // The PC here is to be used at wback stage to track out the
  //  PC of exception of long-pipe instruction
  //各表项中指令的PC
  wire [`E203_PC_SIZE-1:0] pc_r[`E203_OITF_DEPTH-1:0];

  //队尾指针使能
  wire alc_ptr_ena = dis_ena;
  //队首指针使能
  wire ret_ptr_ena = ret_ena;
 
  //oitf是否满了
  wire oitf_full ;
  
  //allocation pointer 队尾指针
  wire [`E203_ITAG_WIDTH-1:0] alc_ptr_r;
  //return pointer 队首指针
  wire [`E203_ITAG_WIDTH-1:0] ret_ptr_r;

  generate
  if(`E203_OITF_DEPTH > 1) begin: depth_gt1//{
      //OTIF中有多个表项
      wire alc_ptr_flg_r;
      wire alc_ptr_flg_nxt = ~alc_ptr_flg_r;
      wire alc_ptr_flg_ena = (alc_ptr_r == ($unsigned(`E203_OITF_DEPTH-1))) & alc_ptr_ena;
      
      sirv_gnrl_dfflr #(1) alc_ptr_flg_dfflrs(alc_ptr_flg_ena, alc_ptr_flg_nxt, alc_ptr_flg_r, clk, rst_n);
      
      wire [`E203_ITAG_WIDTH-1:0] alc_ptr_nxt; 
      
      assign alc_ptr_nxt = alc_ptr_flg_ena ? `E203_ITAG_WIDTH'b0 : (alc_ptr_r + 1'b1);
      
      sirv_gnrl_dfflr #(`E203_ITAG_WIDTH) alc_ptr_dfflrs(alc_ptr_ena, alc_ptr_nxt, alc_ptr_r, clk, rst_n);
      
      
      wire ret_ptr_flg_r;
      wire ret_ptr_flg_nxt = ~ret_ptr_flg_r;
      wire ret_ptr_flg_ena = (ret_ptr_r == ($unsigned(`E203_OITF_DEPTH-1))) & ret_ptr_ena;
      
      sirv_gnrl_dfflr #(1) ret_ptr_flg_dfflrs(ret_ptr_flg_ena, ret_ptr_flg_nxt, ret_ptr_flg_r, clk, rst_n);
      
      wire [`E203_ITAG_WIDTH-1:0] ret_ptr_nxt; 
      
      assign ret_ptr_nxt = ret_ptr_flg_ena ? `E203_ITAG_WIDTH'b0 : (ret_ptr_r + 1'b1);

      sirv_gnrl_dfflr #(`E203_ITAG_WIDTH) ret_ptr_dfflrs(ret_ptr_ena, ret_ptr_nxt, ret_ptr_r, clk, rst_n);

      assign oitf_empty = (ret_ptr_r == alc_ptr_r) &   (ret_ptr_flg_r == alc_ptr_flg_r);
      assign oitf_full  = (ret_ptr_r == alc_ptr_r) & (~(ret_ptr_flg_r == alc_ptr_flg_r));
  end//}
  else begin: depth_eq1//}{
      //OTIF中最多只有一个表项
      assign alc_ptr_r =1'b0;
      assign ret_ptr_r =1'b0;
      //vld_r[0]为0说明一个也没放->otif空
      assign oitf_empty = ~vld_r[0];
      //vld_r[0]为1说明放了一个->otif满了
      assign oitf_full  = vld_r[0];
  end//}
  endgenerate//}

  assign ret_ptr = ret_ptr_r;
  assign dis_ptr = alc_ptr_r;

 //// 
 //// // If the OITF is not full, or it is under retiring, then it is ready to accept new dispatch
 //// assign dis_ready = (~oitf_full) | ret_ena;
 // To cut down the loop between ALU write-back valid --> oitf_ret_ena --> oitf_ready ---> dispatch_ready --- > alu_i_valid
 //   we exclude the ret_ena from the ready signal
 assign dis_ready = (~oitf_full);
  
  wire [`E203_OITF_DEPTH-1:0] rd_match_rs1idx;
  wire [`E203_OITF_DEPTH-1:0] rd_match_rs2idx;
  wire [`E203_OITF_DEPTH-1:0] rd_match_rs3idx;
  wire [`E203_OITF_DEPTH-1:0] rd_match_rdidx;

  genvar i;
  generate //{
      for (i=0; i<`E203_OITF_DEPTH; i=i+1) begin:oitf_entries//{
  
        assign vld_set[i] = alc_ptr_ena & (alc_ptr_r == i);
        assign vld_clr[i] = ret_ptr_ena & (ret_ptr_r == i);
        assign vld_ena[i] = vld_set[i] |   vld_clr[i];
        //vld_nxt； vld_r的下一个值
        assign vld_nxt[i] = vld_set[i] | (~vld_clr[i]);
  
        sirv_gnrl_dfflr #(1) vld_dfflrs(vld_ena[i], vld_nxt[i], vld_r[i], clk, rst_n);
        //Payload only set, no need to clear
        //把传入的数据写到寄存器中
        sirv_gnrl_dffl #(`E203_RFIDX_WIDTH) rdidx_dfflrs(vld_set[i], disp_i_rdidx, rdidx_r[i], clk);
        sirv_gnrl_dffl #(`E203_PC_SIZE    ) pc_dfflrs   (vld_set[i], disp_i_pc   , pc_r[i]   , clk);
        sirv_gnrl_dffl #(1)                 rdwen_dfflrs(vld_set[i], disp_i_rdwen, rdwen_r[i], clk);
        sirv_gnrl_dffl #(1)                 rdfpu_dfflrs(vld_set[i], disp_i_rdfpu, rdfpu_r[i], clk);

        assign rd_match_rs1idx[i] = vld_r[i] & rdwen_r[i] & disp_i_rs1en & (rdfpu_r[i] == disp_i_rs1fpu) & (rdidx_r[i] == disp_i_rs1idx);
        assign rd_match_rs2idx[i] = vld_r[i] & rdwen_r[i] & disp_i_rs2en & (rdfpu_r[i] == disp_i_rs2fpu) & (rdidx_r[i] == disp_i_rs2idx);
        assign rd_match_rs3idx[i] = vld_r[i] & rdwen_r[i] & disp_i_rs3en & (rdfpu_r[i] == disp_i_rs3fpu) & (rdidx_r[i] == disp_i_rs3idx);
        assign rd_match_rdidx [i] = vld_r[i] & rdwen_r[i] & disp_i_rdwen & (rdfpu_r[i] == disp_i_rdfpu ) & (rdidx_r[i] == disp_i_rdidx );
  
      end//}
  endgenerate//}

  assign oitfrd_match_disprs1 = |rd_match_rs1idx;
  assign oitfrd_match_disprs2 = |rd_match_rs2idx;
  assign oitfrd_match_disprs3 = |rd_match_rs3idx;
  assign oitfrd_match_disprd  = |rd_match_rdidx ;

  assign ret_rdidx = rdidx_r[ret_ptr];
  assign ret_pc    = pc_r [ret_ptr];
  assign ret_rdwen = rdwen_r[ret_ptr];
  assign ret_rdfpu = rdfpu_r[ret_ptr];

endmodule


