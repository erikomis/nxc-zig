type GetTemplateTuple<T> = T;
type Message = string;

const printMessage = (...args: ArgTypes) => args;

const pipeline = {
  pipeAsync(value) {
    return value;
  },
};

export const removed = pipeline.pipeAsync(printMessage("Removed :{count} music files.")<[number]>);