/*
Copyright 2017 Tomas Brabec

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Changelog:

  2018, Aug, Tomas Brabec
  - Created.

*/

module spi_model #(
    parameter int SIZE = 2**13
)(
    input  logic sck,
    input  logic rst_n,
    input  logic cs_n,
    input  logic[3:0] dq_i,
    output logic[3:0] dq_o,
    output logic[3:0] dq_t
);

logic [7:0] buffer_in;
logic [7:0] buffer_out;
int cnt_bit;
int cnt_byte;
logic [7:0] cmd = '1;
logic [23:0] addr_base;
int addr_offset;
logic [7:0] mem[0:SIZE-1];
logic [7:0] buffer_in_comb;

task load_file(
    input string path
);
    $display("%0t:\tLoading SPI memory from '%0s' ...", $realtime, path);
    $readmemh(path,mem);
    $display("%0t:\tLoading completed.", $realtime);
endtask: load_file

task mem_set(
    input int addr,
    input logic[7:0] data
);
    if (addr >= 0 && addr < SIZE) begin
        $display("%0t:\tSetting SPI memory at %0d (%0hh) to %hh ...", $realtime, addr, addr, data);
        mem[addr] = data;
        $display("%0t:\t\tmem[%0d]=%hh", $realtime, addr, mem[addr]);
    end
endtask: mem_set

always_ff @(posedge sck or negedge rst_n or posedge cs_n) begin
    if (!rst_n | cs_n) begin
        cnt_bit <= 0;
        cnt_byte <= 0;
    end
    else begin
        cnt_bit <= cnt_bit + 1;
        if ((cnt_bit & 3'd7) == 7) cnt_byte <= cnt_byte + 1;
    end
end

assign buffer_in_comb = {buffer_in[6:0],dq_i[0]};

always_ff @(posedge sck or negedge rst_n) begin
    if (!rst_n)
        buffer_in <= 'x;
    else if (!cs_n)
        buffer_in <= buffer_in_comb;
end

assign dq_o = {2'b00,buffer_out[7],1'b0};
assign dq_t = 4'b1101;

always_ff @(negedge sck or negedge rst_n or posedge cs_n) begin
    int addr;
    if (!rst_n || cs_n) begin
        buffer_out <= '0;
        addr_offset <= 0;
    end
    else if (!cs_n)
        if (cnt_bit > 0 && (cnt_bit & 3'd7) == 0) begin
            if (cmd == 8'hff) begin // loopback
                buffer_out <= buffer_in;
            end
            else if (cmd == 8'h03 && cnt_byte > 3) begin // read
                addr = (cnt_byte == 4) ? addr_base : addr_base + addr_offset + 1;
                addr_offset <= (cnt_byte == 4) ? 0 : addr_offset + 1;
                buffer_out <= (addr < SIZE) ? mem[addr] : 'x;
            end
            else
                buffer_out <= {buffer_out[6:0],1'b0};
        end
        else
            buffer_out <= {buffer_out[6:0],1'b0};
end

always_ff @(posedge sck or negedge rst_n) begin
    if (!rst_n) begin
        cmd <= '1;
        addr_base <= '0;
    end
    else if ((cnt_bit & 3'd7) == 7) begin
        if (cnt_byte == 0) cmd <= buffer_in_comb;
        if (cnt_byte == 1) addr_base[23:16] <= buffer_in_comb;
        if (cnt_byte == 2) addr_base[15: 8] <= buffer_in_comb;
        if (cnt_byte == 3) addr_base[ 7: 0] <= buffer_in_comb;
    end
end

endmodule: spi_model
