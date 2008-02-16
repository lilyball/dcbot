# This file came from Asami (http://asami.rubyforge.org). There is no LICENSE
# distributed with the Asami project. I have no idea what license the Asami project
# is intended to be distributed under, but in the absence of other information I
# will assume the Ruby license.

def huff_insert(arr,node)
	return arr.unshift(node) if arr.length==0
	0.upto(arr.length-1){|i|
		if arr[i].occur>node.occur
			if i>0
				return arr[0..i-1]+[node]+arr[i..arr.length]
			else
				return arr.unshift(node)
			end
		elsif arr[i].occur == node.occur && (node.left==nil)
			if i>0
				return arr[0..i-1]+[node]+arr[i..arr.length]
			else
				return arr.unshift(node)
			end
		end
	}
	return arr.push(node)
end
def add_bit(str,pos,value)
	str << 0 if pos&7==0
	if value!=0
		str[pos/8]|=(1<<(pos&7))
	end
end
def add_bits(str,pos,pattern,len)
	0.upto(len-1){|i|
		add_bit(str,pos,pattern>>(len-1-i)&1)
		pos+=1
	}
end
def get_bit(str,pos)
	((str[pos/8]) >> (pos&7))&1
end
def get_bits(str,start,num)
	res=0
	0.upto(num-1){|i|res=res<<1|get_bit(str,start+i);}
	res
end

class HuffNode
  attr_accessor :left,:right,:occur,:value
  def initialize(occur,value)
    @occur=occur
    @value=value
    @left=nil
    @right=nil
  end
end
class HufEncode
  attr_reader :len,:bits
  def initialize(len,bits)
    @len=len
    @bits=bits
  end
end

def use_hufnode(tbl_enc,node,length,bits)
  if node.left!=nil
    use_hufnode(tbl_enc,node.left,length+1,(bits<<1)|0)
    use_hufnode(tbl_enc,node.right,length+1,(bits<<1)|1)
  else
    idx=node.value&255
    tbl_enc[idx]=HufEncode.new length,bits
  end
end

def he3_encode(str)
  tbl_enc=Array.new
  data=""
  list=Array.new
  nb_val=0
  occur=Array.new 256,0
  if str==nil||str.length==0
    puts "zero length or nil string"
  end
  parity=0
  0.upto(str.length-1){|i|
    occur[(str[i]&255)]+=1
    parity^=str[i]
  }
  0.upto(255){|i|
    if occur[i]!=0
      mw=HuffNode.new(occur[i],i)
      list=huff_insert(list,mw)
      nb_val+=1
    end
  }
  while(list.length>1)
    node=HuffNode.new(0,0)
    node.left=list.shift
    node.right=list.shift
    node.occur=(node.left.occur||0)+(node.right.occur||0)
    list=huff_insert(list,node)
  end
  root_huff=list.shift
  use_hufnode tbl_enc,root_huff,0,0
  header="HE3\r0000000"
  header[4]=(parity&255)
  header[5]=str.length&255
  header[6]=(str.length>>8)&255
  header[7]=(str.length>>16)&255
  header[8]=(str.length>>24)&255
  header[9]=nb_val&255
  header[10]=(nb_val>>8)&255
  data = header
  0.upto(255){|i|
    if occur[i]!=0
      data << i
      data << tbl_enc[i].len
    end
  }
  bit_pos=data.length*8
	0.upto(255){|i|
    if occur[i]!=0
      add_bits(data,bit_pos,tbl_enc[i].bits,tbl_enc[i].len)
      bit_pos+=tbl_enc[i].len;
    end
  }
  bit_pos=(bit_pos+7)&~7
  0.upto(str.length-1){|i|
    idx=str[i]&255
    add_bits(data,bit_pos,tbl_enc[idx].bits,tbl_enc[idx].len)
    bit_pos+=tbl_enc[idx].len
  }
  return data
end

def he3_decode(input)
  unless input[0]==72 && input[1]==69 && input[2]==51 && input[3]==13
    puts "not a valid he3 i guess"
    exit
  end
  nb_output=0
  8.downto(6){|i|
    nb_output|=(input[i]&255)
    nb_output<<=8
  }
  nb_output|=(input[5]&255)
  nb_couple = input[9]
  nb_couple += ((input[10]&255)<<8)
  max_len=0
  total_len=0
  0.upto(nb_couple-1){|pos|
    v = input[12+pos*2]&255
    max_len = v if v>max_len
    total_len+=v
  }
  offset_pattern = 8 *(11+nb_couple*2)
  offset_encoded=offset_pattern + ((total_len+7)&~7)
  decode_array=Array.new max_len*32,0
  0.upto(nb_couple-1){|pos|
    v_len = input[12+pos*2]&255
    value = get_bits(input,offset_pattern,v_len)
    offset_pattern+=v_len
    decode_array[(1<<v_len)+value] = input[11+pos*2]	
  }
  output=""
  while output.length!=(nb_output) do
    cur_val = get_bit(input,offset_encoded)
    offset_encoded+=1
    nb_bit_val=1
    x=decode_array[(1<<nb_bit_val)+cur_val]
    while(x==0||x==nil) do
      cur_val=cur_val<<1|get_bit(input,offset_encoded)
      offset_encoded+=1
      nb_bit_val+=1
      x=decode_array[(1<<nb_bit_val)+cur_val]
    end
    output << (decode_array[(1<<nb_bit_val)+cur_val])
  end
  return output
end


