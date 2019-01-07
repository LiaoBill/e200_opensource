// <!-- 💥BILLLIAO-⚛-FILEHEADER☣ -->
// <!-- ⚡AUTHOR: BillLiaoMX -->
// <!-- 🌶CREATION-DATE: 2019-01-06 21:45:07💦 -->
// <!-- 💤LAST-MODIFY-AUTHOR:   BillLiaoMX💢 -->
// <!-- 💮UPDATE-TIME: 2019-01-06 21:45:07💠 -->

`include "e203_defines.v"

module e203_exu_aluwbck(

  //////////////////////////////////////////////////////////////
  // alu 输入部分 -- input
  // Handshake valid 写回握手请求信号
  input  x_alu_wbck_i_valid,
  // Handshake ready 写回握手反馈信号
  output x_alu_wbck_i_ready,

  // 写囚的数据值 write back data
  input  [`E203_XLEN-1:0] x_alu_wbck_i_wdat,
  // 写田的寄存器索引值, register index
  input  [`E203_RFIDX_WIDTH-1:0] x_alu_wbck_i_rdidx,
  //这边需要改为alu itag
  // 关于itag直接打过来的问题，两种情况
    // 短指令在长指令之前-->这时候itag虽然是长指令，所以我们需要的不是直接连线过来，而是改成寄存器的方式交付过来，现在先直接连线过来，因为还是一个周期执行完了
    // 长指令在短指令之前-->这时候itag就是短指令
  input  [`E203_ITAG_WIDTH -1:0] x_alu_wbck_i_itag,

  // ALU直接提交异常给commit不需要在这边管理异常信息
  // input  lsu_wbck_i_err , // The error exception generated
  // input  lsu_cmt_i_buserr ,
  // input  [`E203_ADDR_SIZE -1:0] lsu_cmt_i_badaddr,
  // 不需要load or store
  // input  lsu_cmt_i_ld, 
  // input  lsu_cmt_i_st, 

  //////////////////////////////////////////////////////////////
  // ALU输出部分 -- output
  // alu 握手
  output alu_wbck_o_valid, // Handshake valid
  input  alu_wbck_o_ready, // Handshake ready

  // output [`E203_FLEN-1:0] longp_wbck_o_wdat,
  // output [5-1:0] longp_wbck_o_flags,
  // output [`E203_RFIDX_WIDTH -1:0] longp_wbck_o_rdidx,
  // output longp_wbck_o_rdfpu,
  // 写囚的数据值 write back data
  output  [`E203_XLEN-1:0] alu_wbck_o_wdat,
  // 写田的寄存器索引值, register index
  output  [`E203_RFIDX_WIDTH-1:0] alu_wbck_o_rdidx,
  //这边需要改为alu itag
  // input  [`E203_ITAG_WIDTH -1:0] alu_wbck_o_itag,

  // --------- add/modify/delete code ---------异常不需要
  // The Long pipe instruction Exception interface to commit stage
  // output  longp_excp_o_valid,
  // input   longp_excp_o_ready,
  // output  longp_excp_o_insterr,
  // output  longp_excp_o_ld,
  // output  longp_excp_o_st,
  // output  longp_excp_o_buserr , // The load/store bus-error exception generated
  // output [`E203_ADDR_SIZE-1:0] longp_excp_o_badaddr,
  // output [`E203_PC_SIZE -1:0] longp_excp_o_pc,
  //
  // --------- add/modify/delete code ---------
  // --------- add/modify/delete code ---------
  //The itag of toppest entry of OITF
  input  oitf_empty,
  input  [`E203_ITAG_WIDTH -1:0] oitf_ret_ptr,
  // input  [`E203_RFIDX_WIDTH-1:0] oitf_ret_rdidx,
  // // input  [`E203_PC_SIZE-1:0] oitf_ret_pc,
  // input  oitf_ret_rdwen,
  // // input  oitf_ret_rdfpu,
  output oitf_ret_ena,
  // --------- add/modify/delete code ---------
  
  input  clk,
  input  rst_n
  );

  // The Long-pipe instruction can write-back only when it's itag 
  //   is same as the itag of toppest entry of OITF
  // oitf不能是空的，不然没东西删除也没必要删除
  // oitf_ret_ptr队首的物体和当前要写回的itag一样，那么我们才能进行写会
  // 也就是说我们在ALU这里加一个判断就好了
  // wire wbck_ready4lsu = (lsu_wbck_i_itag == oitf_ret_ptr) & (~oitf_empty);
  // wire wbck_sel_lsu = lsu_wbck_i_valid & wbck_ready4lsu;
  // --------- add/modify/delete code ---------模仿上方的写法即可
  // 为了测试先设置为永真
  // wire wbck_ready4alu = (x_alu_wbck_i_itag == oitf_ret_ptr) & (~oitf_empty);
  wire wbck_ready4alu = 1'b1 | (x_alu_wbck_i_itag == oitf_ret_ptr) & (~oitf_empty);
  wire wbck_sel_alu = x_alu_wbck_i_valid & wbck_ready4alu;

  // 异常处理不需要
  //assign longp_excp_o_ld   = wbck_sel_lsu & lsu_cmt_i_ld;
  //assign longp_excp_o_st   = wbck_sel_lsu & lsu_cmt_i_st;
  //assign longp_excp_o_buserr = wbck_sel_lsu & lsu_cmt_i_buserr;
  //assign longp_excp_o_badaddr = wbck_sel_lsu ? lsu_cmt_i_badaddr : `E203_ADDR_SIZE'b0;

  // 异常处理不需要
  // assign {
  //        longp_excp_o_insterr
  //       ,longp_excp_o_ld   
  //       ,longp_excp_o_st  
  //       ,longp_excp_o_buserr
  //       ,longp_excp_o_badaddr } = 
  //            ({`E203_ADDR_SIZE+4{wbck_sel_lsu}} & 
  //             {
  //               1'b0,
  //               lsu_cmt_i_ld,
  //               lsu_cmt_i_st,
  //               lsu_cmt_i_buserr,
  //               lsu_cmt_i_badaddr
  //             }) 
  //             ;

  //////////////////////////////////////////////////////////////
  // The Final arbitrated Write-Back Interface
  wire wbck_i_ready;
  wire wbck_i_valid;
  wire [`E203_XLEN-1:0] wbck_i_wdat;
  // wire [5-1:0] wbck_i_flags;
  wire [`E203_RFIDX_WIDTH-1:0] wbck_i_rdidx;
  // wire [`E203_PC_SIZE-1:0] wbck_i_pc;
  wire wbck_i_rdwen;
  // wire wbck_i_rdfpu;
  wire wbck_i_err ;

  // assign lsu_wbck_i_ready = wbck_ready4lsu & wbck_i_ready;
  // --------- add/modify/delete code ---------
  assign x_alu_wbck_i_ready = wbck_ready4alu & wbck_i_ready;

  // assign wbck_i_valid = ({1{wbck_sel_lsu}} & lsu_wbck_i_valid) 
  // --------- add/modify/delete code ---------
  assign wbck_i_valid = ({1{wbck_sel_alu}} & x_alu_wbck_i_valid);


  // `ifdef E203_FLEN_IS_32 //{
  wire [`E203_XLEN-1:0] alu_wbck_i_wdat_exd = x_alu_wbck_i_wdat;
  // `else//}{
  // wire [`E203_XLEN-1:0] lsu_wbck_i_wdat_exd = {{`E203_XLEN-`E203_XLEN{1'b0}},lsu_wbck_i_wdat};
  // `endif//}
  assign wbck_i_wdat  = ({`E203_XLEN{wbck_sel_alu}} & alu_wbck_i_wdat_exd ) 
                         ;
  // assign wbck_i_flags  = 5'b0
                         ;
  // assign wbck_i_err   = wbck_sel_lsu & lsu_wbck_i_err 
  //                        ;

  // assign wbck_i_pc    = oitf_ret_pc;
  assign wbck_i_rdidx = x_alu_wbck_i_rdidx;
  // assign wbck_i_rdwen = oitf_ret_rdwen;
  // assign wbck_i_rdfpu = oitf_ret_rdfpu;

  // If the instruction have no error and it have the rdwen, then it need to 
  //   write back into regfile, otherwise, it does not need to write regfile
  // wire need_wbck = wbck_i_rdwen & (~wbck_i_err);
  // --------- add/modify/delete code ---------
  // wire need_wbck = wbck_i_rdwen;
  // wire need_wbck = 1'b1 | wbck_i_rdwen;

  // If the long pipe instruction have error result, then it need to handshake
  //   with the commit module.
  // wire need_excp = wbck_i_err;

  // assign wbck_i_ready = 
  //      (need_wbck ? longp_wbck_o_ready : 1'b1)
  //    & (need_excp ? longp_excp_o_ready : 1'b1);
  assign wbck_i_ready = 
       alu_wbck_o_ready;
     // & (need_excp ? longp_excp_o_ready : 1'b1); no  exception needed

  // --------- add/modify/delete code ---------
  // 不需要处理异常
  // assign longp_wbck_o_valid = need_wbck & wbck_i_valid & (need_excp ? longp_excp_o_ready : 1'b1);
  assign alu_wbck_o_valid = wbck_i_valid;
  // --------- add/modify/delete code ---------
  // 不需要异常处理
  // assign longp_excp_o_valid = need_excp & wbck_i_valid & (need_wbck ? longp_wbck_o_ready : 1'b1);

  assign alu_wbck_o_wdat  = wbck_i_wdat ;
  // assign longp_wbck_o_flags = wbck_i_flags ;
  // assign alu_wbck_o_rdfpu = wbck_i_rdfpu ;
  assign alu_wbck_o_rdidx = wbck_i_rdidx;

  // assign longp_excp_o_pc    = wbck_i_pc;

  // 为了测试牺牲一下, 写回了才会ready，才去除oitf中的数值
  // assign oitf_ret_ena = wbck_i_valid & wbck_i_ready;
  // 代表向后说我要写回并且后面回复说已经写好了，才将ret_ena设置为true，也就是删掉当前项目
  assign oitf_ret_ena = wbck_i_valid & wbck_i_ready;

endmodule                                      
                                               
        